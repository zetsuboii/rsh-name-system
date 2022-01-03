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
	name: Bytes(64),
	pricePerDay: UInt
});

const Price = Data({
	NotForSale: Null,
	ForSale: UInt 
});

// Interfaces
const DomainViews = {
	name: Bytes(64),
	owner: Address,
	resolver: Address,
	ttl: UInt,
	price: Price,
	isAvailable: Fun([], Bool)
};

const CreatorInterface = {
	getParams: Fun([], NftParams),
	announce: Fun([], Null)
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

	// setOptions({ verifyPerConnector: true });
	deploy();
	
	// Creator sets the parameters
	Creator.only(() => {
		const { name, pricePerDay } = d(interact.getParams());
	});
	Creator.publish(name, pricePerDay);
	
	commit();

	Creator.interact.announce();
	Creator.publish();

	Views.name.set(name);

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

			// Allow if registering for the first time or if it's expired
			const isAvailable = () => 
				state.ttl == 0 || lastConsensusTime() > state.ttl + GRACE_PERIOD;

			const isOwner = (addr) => addr === state.owner;
		})
		.api(User.register,
			(duration) => {
				assume(duration >= MIN_REGISTER_PERIOD);
				assume(isAvailable());
				assume(!isOwner(this));
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(isAvailable());
				require(!isOwner(this));
				ok(true);

				transfer(balance()).to(Creator);

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
				assume(isOwner(this));
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				require(isOwner(this));
				ok(true);

				transfer(balance()).to(Creator);

				return {
					...state,
					ttl: state.ttl + duration
				} 
			}
		)
		.api(User.isAvailable,
			(showIfAvailable) => {
				showIfAvailable(isAvailable());
				return state;
			}	
		)
		.api(User.setResolver,
			(newResolver) => {
				assume(newResolver != state.resolver);
				assume(isOwner(this));
			},
			(_) => 0,
			(newResolver, ok) => {
				require(newResolver != state.resolver);
				require(isOwner(this));
				ok(true);

				return {
					...state,
					resolver: newResolver
				};
			}
		)
		.api(User.transferTo,
			(newOwner) => {
				assume(newOwner != state.owner);
				assume(isOwner(this));
			},
			(_) => 0,
			(newOwner, ok) => {
				require(newOwner != state.owner);
				require(isOwner(this));
				ok(true);

				return {
					...state,
					owner: newOwner,
					resolver: newOwner,
					price: Price.NotForSale()
				};
			}
		)
		.api(User.list,
			(newPrice) => {
				assume(newPrice > 0);
				assume(isOwner(this));
			},
			(_) => 0,
			(newPrice, ok) => {
				require(newPrice > 0);
				require(isOwner(this));
				ok(true);

				return {
					...state,
					price: Price.ForSale(newPrice)
				};
			}
		)
		.api(User.buy,
			() => {
				assume(state.price != Price.NotForSale());
				assume(!isOwner(this));
			},
			() => getPrice(state.price),
			(ok) => {
				require(state.price != Price.NotForSale());
				require(!isOwner(this));
				ok(true);

				transfer(balance()).to(state.owner);

				return {
					...state,
					owner: this,
					resolver: this,
					price: Price.NotForSale()
				}; 
			} 
		)
		.timeout(relativeSecs(1024), () => {
			Anybody.publish();
			return state;
		});

	commit();
	exit();
});
