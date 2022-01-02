'reach 0.1';

// Helpers
const d = declassify;

// Types
const NftParams = Object({
	name: Bytes(32),
	symbol: Bytes(32)
});

// Interfaces
const DomainViews = {

};

const CreatorInterface = {
	getParams: Fun([], NftParams)
};

const UserInterface = {

};

export const main = Reach.App(() => {
	const Creator = Participant("Creator", CreatorInterface);
	const User = API("User", UserInterface);
	const Views = View(DomainViews);
	deploy();

	// Creator sets the parameters
	Creator.only(() => {
		const { name, symbol } = d(interact.getParams());
	});
	Creator.publish(name, symbol);

	commit();
	exit();
});
