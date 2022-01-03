'reach 0.1';

// Helpers
const d = declassify;

// Types
const NftParams = Object({
	name: Bytes(32),
	symbol: Bytes(32),
	pricePerDay: UInt
});

// Interfaces
const DomainViews = {

};

const CreatorInterface = {
	getParams: Fun([], NftParams)
};

const UserAPIInterface = {
	// Register functions
	register: Fun([UInt], Bool),
	renew: Fun([UInt], Bool),
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

	/*
	 * Thinking about it, there are some sanity checks with owner/resolver
	 * changing function which might not be necessary.
	 */

	// Main loop
	const [owner, resolver, ttl, price] = parallelReduce([Creator, Creator, 0, 0])
		.invariant(balance() == 0)
		.while(true)
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

				return [this, this, lastConsensusTime() + duration, 0];
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

				return [owner, resolver, ttl + duration, price];
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

				return [owner, newResolver, ttl, price];
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

				return [newOwner, newOwner, ttl, price]
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

				return [owner, resolver, ttl, newPrice];
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

				return [this, this, ttl, 0];
			} 
		)
		.timeout(relativeSecs(1024), () => {
			Anybody.publish();
			return [owner, resolver, ttl, price];
		});

	commit();
	exit();
});
