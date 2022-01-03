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
	// // Marketplace
	// list: Fun([UInt], Bool),
	// buy: Fun([UInt], Bool)
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

	/**
	 * Thinking about it, there are some sanity checks with owner/resolver
	 * changing function which might not be necessary.
	 */

	// Main loop
	const [owner, resolver, ttl] = parallelReduce([Creator, Creator, 0])
		.invariant(balance() == 0)
		.while(true)
		.api(User.register,
			(duration) => {
				assume(duration >= MIN_REGISTER_PERIOD);
				assume(owner == Creator);
				assume(this != owner);
			},
			(duration) => (duration * pricePerDay) / DAYS_TO_SECS,
			(duration, ok) => {
				require(duration >= MIN_REGISTER_PERIOD);
				// TODO: Change this with expire mechanism
				require(owner == Creator);
				require(this != owner);
				ok(true);

				return [this, this, lastConsensusTime() + duration];
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

				return [owner, resolver, ttl + duration];
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

				return [owner, newResolver, ttl];
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

				return [newOwner, newOwner, ttl]
			}
		)
		.timeout(relativeSecs(1024), () => {
			Anybody.publish();
			return [owner, resolver, ttl];
		});

	commit();
	exit();
});
