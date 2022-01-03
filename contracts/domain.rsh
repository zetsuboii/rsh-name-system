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
	// renew: Fun([UInt], Bool),
	// // Resolve
	// setResolver: Fun([Address], Bool),
	// // Transfers
	// transferTo: Fun([Address], Bool),
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

	// Main loop
	const [owner, resolver, ttl] = parallelReduce([Creator, Creator, 0])
		.invariant(balance() == 0)
		.while(true)
		.timeout(relativeSecs(1024), () => {
			Anybody.publish();
			return [owner, resolver, ttl];
		});

	commit();
	exit();
});
