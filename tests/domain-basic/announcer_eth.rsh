'reach 0.1';

const Iface = Bytes(64);
const Addr = Address;

export const main = Reach.App(() => {
    const Constructor = Participant('Constructor', {
        printInfo: Fun([], Null),
        save: Fun([Addr, Iface], Null)
    });
    const ConstructorAPI = API('Allower', {
        allow: Fun([Address], Bool)
    })
    const ManagerAPI = API('Manager', {
        register: Fun([Addr, Iface], Bool)
    });
    deploy();

    Constructor.publish();
    Constructor.interact.printInfo();

    const ownerAddress = this;
    const allowedToRegister = new Map(Bool);

    const [] = parallelReduce([])
        .invariant(balance() == 0)
        .while(true)
        .api(ConstructorAPI.allow,
            (_) => {
                assume(this == ownerAddress);
            },
            (_) => 0,
            (addr, ok) => {
                ok(true);
                allowedToRegister[addr] = true;
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