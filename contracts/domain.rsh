'reach 0.1';

// Helpers
const d = declassify;
const getPrice = (p) => {
	return p.match({
		NotForSale: () => { return 0 },
		ForSale: (v) => { return v } 
	});
};

// Types
const NftParams = Object({
	name: Bytes(32),
	symbol: Bytes(32),
	pricePerDay: UInt
});

const Price = Data({
	NotForSale: Null,
	ForSale: UInt 
});

// Interfaces
const DomainViews = {
	owner: Address,
	resolver: Address,
	ttl: UInt,
	price: Price,
	isAvailable: Fun([], Bool)
};

const CreatorInterface = {
	getParams: Fun([], NftParams)
};

const UserAPIInterface = {
	// Register functions
	register: Fun([UInt], Bool),
	renew: Fun([UInt], Bool),
	isAvailable: Fun([], Bool),
	// Resolve
	setResolver: Fun([Address], Bool),
	// Transfers
	transferTo: Fun([Address], Bool),
	// Marketplace
	list: Fun([UInt], Bool),
	buy: Fun([], Bool)
};

const DAYS_TO_SECS = 24 * 60 * 60;

const GRACE_PERIOD = 90 * DAYS_TO_SECS;
const MIN_REGISTER_PERIOD = 30 * DAYS_TO_SECS;

export const main = Reach.App(() => {
	const Creator = Participant("Creator", CreatorInterface);
	const User = API("User", UserAPIInterface);
	const Views = View(DomainViews);

	setOptions({ verifyPerConnector: true });
	deploy();

	// Creator sets the parameters
	Creator.only(() => {
		const { name, symbol, pricePerDay } = d(interact.getParams());
	});
	Creator.publish(name, symbol, pricePerDay);
	commit();

	// This is needed to observe consensus time
	Creator.publish();

	const initialState = {
		owner: Creator,
		resolver: Creator,
		ttl: 0,
		price: Price.NotForSale()
	}

	// Main loop
	const state = parallelReduce(initialState)
		.invariant(balance() == 0)
		.while(true)
		.define(() => {
			Views.owner.set(state.owner);
			Views.resolver.set(state.resolver);
			Views.ttl.set(state.ttl);
			Views.price.set(state.price);

			const isAvailable = () => 
				state.ttl == 0 || lastConsensusTime() > state.ttl + GRACE_PERIOD;
		})
		.api(User.register,
			(duration) => {
				assume(duration >= MIN_REGISTER_PERIOD);
				// Allow if registering for the first time or if it's expired
				assume(state.ttl == 0 || lastConsensusTime() > state.ttl + GRACE_PERIOD);
				assume(this != state.owner);
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(state.ttl == 0 || lastConsensusTime() > state.ttl + GRACE_PERIOD);
				require(this != state.owner);
				ok(true);

				return {
					owner: this,
					resolver: this,
					ttl: lastConsensusTime() + duration,
					price: Price.NotForSale()
				};
			})
		.api(User.renew,
			(duration) => {
				assume(duration >= MIN_REGISTER_PERIOD);;
				assume(this == state.owner);
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(this == state.owner);
				ok(true);

				return {
					...state,
					ttl: state.ttl + duration
				} 
				// [owner, resolver, ttl + duration, price];
			}
		)
		.api(User.isAvailable,
			(showIfAvailable) => {
				showIfAvailable(
					state.ttl == 0 || 
					lastConsensusTime() > state.ttl + GRACE_PERIOD
				);

				return state;
			}	
		)
		.api(User.setResolver,
			(newResolver) => {
				assume(newResolver != state.resolver);
				assume(this == state.owner);
			},
			(_) => 0,
			(newResolver, ok) => {
				require(newResolver != state.resolver);
				require(this == state.owner);
				ok(true);

				return {
					...state,
					resolver: newResolver
				};
				// [owner, newResolver, ttl, price];
			}
		)
		.api(User.transferTo,
			(newOwner) => {
				assume(newOwner != state.owner);
				assume(this == state.owner);
			},
			(_) => 0,
			(newOwner, ok) => {
				require(newOwner != state.owner);
				require(this == state.owner);
				ok(true);

				return {
					...state,
					owner: newOwner,
					resolver: newOwner,
					price: Price.NotForSale()
				};
				// [newOwner, newOwner, ttl, price]
			}
		)
		.api(User.list,
			(newPrice) => {
				assume(newPrice > 0);
				assume(this == state.owner);
			},
			(_) => 0,
			(newPrice, ok) => {
				require(newPrice > 0);
				require(this == state.owner);
				ok(true);

				return {
					...state,
					price: Price.ForSale(newPrice)
				};
				// [owner, resolver, ttl, newPrice];
			}
		)
		.api(User.buy,
			() => {
				assume(this != state.owner);
				assume(state.price != Price.NotForSale());
			},
			() => getPrice(state.price),
			(ok) => {
				require(this != state.owner);
				require(state.price != Price.NotForSale());
				ok(true);

				return {
					...state,
					owner: this,
					resolver: this,
					price: Price.NotForSale()
				}; 
				// [this, this, ttl, 0];
			} 
		)
		.timeout(relativeSecs(1024), () => {
			Anybody.publish();
			return state;
		});

	commit();
	exit();
});
