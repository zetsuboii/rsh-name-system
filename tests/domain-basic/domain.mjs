import * as announcer from './build/announcer.main.mjs';
import * as domain from './build/domain.main.mjs';
import {loadStdlib} from '@reach-sh/stdlib';

const NETWORK = process.env["REACH_CONNECTOR_MODE"];
const stdlib = loadStdlib(NETWORK);

const sleep = async (t) => await new Promise(r => setTimeout(r, t * 1000));
const toDays = (t) => t * 24 * 60 * 60;
const getAddress = acc => NETWORK.includes("ALGO") 
  ? acc.networkAccount.addr
  : acc.networkAccount.address;

const waitFor = async (condGet) => {
  return await new Promise(async (res) => {
    while(true) {
      if(condGet()) {
        break;
      }
      await sleep(2);
    }
    res();
  });
}

const tryCall = async (fn, ...args) => {
  return await new Promise(async (res, reject) => {
    let tries = 0;
    let result = null;
    while(true) {
      try {
        const req = await fn(...args);
        result = req[1];
        break;
      } 
    catch(e) { 
      tries += 1; 
      if(tries >= 5) 
        reject("Failed to call API")
    }
    await sleep(2);
  }
  res(result);
})};

const view = async (f, ...args) => {
  const result = await f(...args)
  return result[0] === "Some" ? result[1] : null;
} 

const fmtDetails = async (views) => {
  const name = await view(views.name);
  const owner =  await view(views.owner);
	const resolver =  await view(views.resolver);
	const ttl =  await view(views.ttl);
	const price =  await view(views.price);
	const isAvailable = await view(views.isAvailable);

  const ttld = new Date(ttl * 1000);
  const priceTag = price[0] === "NotForSale"
    ? "Not For Sale"
    : "On Sale for " + stdlib.formatCurrency(price[1]) + " network tokens";

  return `Details:\n\tDomain name: ${name}\n\t` +
  `Owner: ${owner}\n\t` +
  `Resolves to: ${resolver}\n\t` +
  `Time to live: ${ttld.toLocaleString()}\n\t` +
  `Price: ${priceTag}\n\t` +
  `Is available: ${isAvailable}`
}

const listDomains = (li) => {
  li.forEach((v, i) => {
    console.log(`[${i}]:`, v.appId, "->", v.iface);
  });
}

(async () => {
  console.log("Loading stdlib...");
  const startingBalance = stdlib.parseCurrency(100);
  await new Promise(res => setTimeout(res, 100));

  const [ accConstructor, accCreator, accAlice, accBob ] =
    await stdlib.newTestAccounts(4, startingBalance);

  const domainsList = [];

  const ctcConstructor = accConstructor.contract(announcer);
  let allowedCreator = false;
  const runConstructor = async () => {
    await announcer.Constructor(ctcConstructor, {
      printInfo: async () => {
        console.log("Announcer Contract Info:", 
          JSON.stringify(await ctcConstructor.getInfo()));
      },
      save: (appId, iface) => {
        console.log(`Saved contract info: { appId: ${appId.toString()}, interface: ${iface} }`);
        domainsList.push({appId: appId.toString(), iface});
      }
    });    
  };

  const allowCreator = async () => {
    const fns = ctcConstructor.apis.Allower;

    await tryCall(fns.allow, getAddress(accCreator));
    allowedCreator = true;
    console.log("Allowed creator");
  }

  const ctcCreator = accCreator.contract(domain);
  const createDomain = async (domainName) => {
    await waitFor(() => allowedCreator);

    await domain.Creator(ctcCreator, {
      getParams: async () => {
        console.log("Creator is setting domain parameters");
        return {
          name: domainName,
          pricePerDay: stdlib.parseCurrency(0.1)
        }
      },
      announce: async () => {
        console.log("Creator announces the contract");
        const address = await ctcCreator.getInfo();
        console.log("Domain contract:", address);
        const announcerContract = accCreator.contract(announcer, 
          await ctcConstructor.getInfo());
        
        const fns = announcerContract.apis.Manager;
        await tryCall(fns.register, address, "Domain");
      },
    });
  }

  const runUsers = async () => {
    await waitFor(() => domainsList.length > 0);
    console.log(`Alice found an application with ID: ${domainsList[0].appId}`);

    const aliceDomainCtc = accAlice.contract(domain, domainsList[0].appId);
    const bobDomainCtc = accBob.contract(domain, domainsList[0].appId);
    listDomains(domainsList);

    console.log("Alice learns domain name of the app is", 
                 await view(aliceDomainCtc.v.name));
    
    console.log(JSON.stringify({
      aliceAddress: getAddress(accAlice),
      bobAddress: getAddress(accBob),
      contractAddress: domainsList[0].appId,
      creatorAddress: getAddress(accCreator)
    }, null, 2));
      
    const alicefns = aliceDomainCtc.apis.User;
    const bobfns = bobDomainCtc.apis.User;

    console.log("Alice tries to register");
    await tryCall(alicefns.register, toDays(90));
    console.log(await fmtDetails(aliceDomainCtc.v));
    
    console.log("Alice tries to change the resolver");
    await tryCall(alicefns.setResolver, getAddress(accBob));
    console.log(await fmtDetails(aliceDomainCtc.v));

    console.log("Alice tries to transfer it to Bob");
    await tryCall(alicefns.transferTo, getAddress(accBob));
    console.log(await fmtDetails(aliceDomainCtc.v));

    console.log("Bob lists the domain for 5 network tokens");
    await tryCall(bobfns.list, stdlib.parseCurrency(5));
    console.log(await fmtDetails(aliceDomainCtc.v));

    console.log("Alice buys the domain");
    await tryCall(alicefns.buy);
    console.log(await fmtDetails(aliceDomainCtc.v));

    process.exit(0);
  }
    
  console.log('Starting backends...');
  await Promise.all([
    runConstructor(),
    allowCreator(),
    createDomain("hamza.algo"),
    runUsers()
  ]);
})();
