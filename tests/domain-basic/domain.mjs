import * as announcer from './build/announcer.main.mjs';
import * as domain from './build/domain.main.mjs';
import {loadStdlib} from '@reach-sh/stdlib';

const sleep = async (t) => await new Promise(r => setTimeout(r, t * 1000));
const call = async(fn, ...args) => await new Promise(async (res, rej) => {
  try {
    const result = await fn(args);
    if(result[0] === "Some")
      res(result[1]);
    else
      res(null)
  }
  catch(e) { 
    console.log("Call failed");
    res(null) 
  }
});

(async () => {
  console.log("Loading stdlib...");
  const stdlib = loadStdlib("ETH");
  const startingBalance = stdlib.parseCurrency(100);

  console.log('Launching...');
  await new Promise(res => setTimeout(res, 100));

  const [ accConstructor, accCreator, accAlice, accBob ] =
    await stdlib.newTestAccounts(4, startingBalance);

  const domainsList = [];

  const ctcConstructor = accConstructor.contract(announcer);
  let allowedCreator = false;
  const runConstructor = async () => {
    await announcer.Constructor(ctcConstructor, {
      printInfo: async () => {
        console.log("Announcer Contract Info:", await ctcConstructor.getInfo());
      },
      save: (appId, iface) => {
        console.log(`Saved contract info: { appId: ${appId.toString()}, interface: ${iface} }`);
        domainsList.push({appId: appId.toString(), iface});
      }
    });    
  };

  const allowCreator = async () => {
    while(true) {
      try {
        const result = await ctcConstructor.apis.Allower.allow(
          accCreator.networkAccount.address);
        console.log("Allowed", result);
        allowedCreator = true;
        break;
      }   
      catch(e) {} 
      await sleep(2);
    }
  }

  const ctcCreator = accCreator.contract(domain);
  const runCreator = async () => {
    await new Promise(async (res) => {
      while(true) {
        console.log("Creator is waiting for approval");
        if(allowedCreator) {
          console.log("Creator is approved");
          await sleep(1);
          break;
        }
        await sleep(2);
      }
      res();
    });

    await domain.Creator(ctcCreator, {
      getParams: async () => {
        console.log("Creator is setting domain parameters");
        return {
          name: "hamza.algo",
          pricePerDay: stdlib.parseCurrency(0.1)
        }
      },
      announce: async () => {
        console.log("Creator announces the contract");
        const address = await ctcCreator.getInfo();
        console.log("Domain contract:", address);
        const announcerContract = accCreator.contract(announcer, await ctcConstructor.getInfo());
        const fns = announcerContract.apis.Manager;

        while(true) {
          try {
            const result = await fns.register(
              address,
              "Domain"
            );
            console.log("Registered:", result);
            break;
          }
          catch(e) {
            console.log("Error with Manager API", e);
          }
          await sleep(2);
        }
      },
    });
  }

  const runAlice = async () => {
    await new Promise(async (res) => {
      while (true) {
        console.log("Alice is looking for domains to buy");
        if(domainsList.length > 0)
          break;
        await sleep(2);
      }
      res();
    });
    console.log(`Alice found an application with ID: ${stdlib.formatAddress(domainsList[0].appId)}`);
    const domainContract = accAlice.contract(domain, domainsList[0].appId);

    const domainView = await domainContract.v.name();
    const domainName = domainView[0] === "Some" ? `${domainView[1]}` : undefined;
    console.log("Alice learns domain name of the app is", domainName);

    console.log({
      aliceAddress: accAlice.networkAccount.address,
      contractAddress: domainsList[0].appId,
      creatorAddress: accCreator.networkAccount.address
    });

    const fns = domainContract.apis.User;
    await new Promise(async (res) => {
      while(true) {
        try {
          const req = await fns.register(90 * 24 * 60 * 60);
          // const req = await fns.isAvailable();
          console.log("Request", req);
          break;
        } 
        catch(e) { }
        await sleep(2);
      }
      res();
    });
    
    console.log("New owner: ", await domainContract.v.owner());
    console.log("New resolver: ", await domainContract.v.resolver());
    
  }
    
  console.log('Starting backends...');
  await Promise.all([
    runConstructor(),
    allowCreator(),
    runCreator(),
    runAlice()
  ]);
})();
