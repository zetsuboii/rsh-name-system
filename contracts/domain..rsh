'reach 0.1';

const DomainViews = {

}

const CreatorInterface = {

};

const UserInterface = {

};

export const main = Reach.App(() => {
  const Creator = Participant("Creator", CreatorInterface);
  const User = API("User", UserInterface);
  const Views = View(DomainViews);
  deploy();
  
});
