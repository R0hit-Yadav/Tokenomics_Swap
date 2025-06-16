module dxlyn::wdxlyn_coin {
    use std::signer;
    use std::string::utf8;
    use supra_framework::coin::{Self, BurnCapability, MintCapability};
    friend dxlyn::dxlyn_swap;

    struct DXLYN has store, drop {}

    const ERROR_NOT_ADMIN: u64 = 1000;

    const DEV: address = @dev;

    struct Caps has key {
        mint: MintCapability<DXLYN>,
        burn: BurnCapability<DXLYN>,
    }

    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == DEV, ERROR_NOT_ADMIN);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<DXLYN>(
            admin,
            utf8(b"wDXLYN Coin"),
            utf8(b"wDXLYN"),
            8,
            true
        );
        coin::destroy_freeze_cap(freeze_cap);
        move_to(admin, Caps {
            mint: mint_cap,
            burn: burn_cap
        });
    }

    public(friend) fun init_module_wdxlyn(admin: &signer) {
        init_module(admin);
    }

    public(friend) fun mint_dxlyn(admin: address, amount: u64): supra_framework::coin::Coin<DXLYN> acquires Caps {
        let caps = borrow_global<Caps>(admin);
        supra_framework::coin::mint<DXLYN>(amount, &caps.mint)
    }

    public(friend) fun burn_dxlyn(admin: address, coin: supra_framework::coin::Coin<DXLYN>) acquires Caps {
        let caps = borrow_global<Caps>(admin);
        supra_framework::coin::burn<DXLYN>(coin, &caps.burn)
    }
}
