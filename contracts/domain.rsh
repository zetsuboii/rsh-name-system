'reach 0.1';

// Helpers
const d = declassify;

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
				assume(ttl == 0 || lastConsensusTime() > ttl + GRACE_PERIOD);
				assume(this != owner);
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(ttl == 0 || lastConsensusTime() > ttl + GRACE_PERIOD);
				require(this != owner);
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
				assume(this == owner);
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(this == owner);
				ok(true);

				return {
					...state,
					ttl: ttl + duration
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
			}	
		)
		.api(User.setResolver,
			(newResolver) => {
				assume(newResolver != resolver);
				assume(this == owner);
			},
			(_) => 0,
			(newResolver, ok) => {
				require(newResolver != resolver);
				require(this == owner);
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
				assume(newOwner != owner);
				assume(this == owner);
			},
			(_) => 0,
			(newOwner, ok) => {
				require(newOwner != owner);
				require(this == owner);
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
				assume(this == owner);
			},
			(_) => 0,
			(newPrice, ok) => {
				require(newPrice > 0);
				require(this == owner);
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
				assume(this != owner);
				assume(price > 0);
			},
			() => price,
			(ok) => {
				require(this != owner);
				require(price > 0);
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
