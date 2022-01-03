'reach 0.1';

const d = declassify
const Iface = Bytes(64);

export const main = Reach.App(() => {
    const Constructor = Participant('Constructor', {
        printInfo: Fun([], Null),
        allow: Fun([], Address),
        save: Fun([UInt, Iface], Null)
    });
    const ManagerAPI = API('Manager', {
        register: Fun([UInt, Iface], Bool)
    });
    deploy();

    Constructor.publish();
    Constructor.interact.printInfo();

    const allowedToRegister = new Map(Bool);

    const [] = parallelReduce([])
        .invariant(balance() == 0)
        .while(true)
        .case(
            Constructor,
            () => { 
                const allowed = d(interact.allow());
                return { msg: allowed }
            },
            (msg) => 0,
            (msg) => {
                allowedToRegister[msg] = true;
                return [];
            }
        )
        .api(
            ManagerAPI.register,
            (_,_) => {
                assume(fromSome(allowedToRegister[this], false)); 
            },
            (_,_) => 0,
            (appId, iface, ok) => {
                require(fromSome(allowedToRegister[this], false));
                ok(true);

                Constructor.interact.save(appId, iface);
                return [];
            }
        )
        .timeout(relativeSecs(1024), () => {
            Anybody.publish();
            return [];
        });

    commit();
    exit();

});