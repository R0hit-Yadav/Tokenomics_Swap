module dxlyn::dxlyn_coin {
    use std::signer;
    use std::string::utf8;

    use supra_framework::coin::{Self, BurnCapability, MintCapability};
    use supra_framework::supra_account;
    use supra_framework::timestamp;

    #[test_only]
    use std::option;
    #[test_only]
    use std::signer::address_of;
    #[test_only]
    use supra_framework::fungible_asset::{Self, Metadata, MintRef};
    #[test_only]
    use supra_framework::object;
    #[test_only]
    use supra_framework::primary_fungible_store;

    struct DXLYN {}

    const WEEK: u64 = 7 * 86400;

    const DEV: address = @dev;

    #[test_only]
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
    }


    #[test_only]
    public fun init_coin(account: &signer) {
        let constructor_ref = &object::create_named_object(account, b"DXLYN");

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"DXLYN Coin"), /* name */
            utf8(b"DXLYN"), /* symbol */
            8, /* decimals */
            utf8(b"http://example.com/favicon.ico"), /* icon */
            utf8(b"http://example.com"), /* project */
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);

        let siger = object::generate_signer(constructor_ref);

        move_to(&siger, ManagedFungibleAsset { mint_ref });

       
    }

    #[test_only]
    public fun register_and_mint(account: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
        let object_add = object::create_object_address(&address_of(account), b"DXLYN");

        let cap = borrow_global<ManagedFungibleAsset>(object_add);

        let coin = fungible_asset::mint(&cap.mint_ref, amount);

        let asset = object::address_to_object<Metadata>(object_add);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);

        fungible_asset::deposit(to_wallet, coin);
    }

    #[test_only]
    public fun get_dxlyn_metadata(account: &signer): address {
        object::create_object_address(&address_of(account), b"DXLYN")
    }

    #[test_only]
    public fun get_user_dxlyn_balance(user_addr: address): u64 {
        //usdt coin metadata
        let dxlyn_coin_address = object::create_object_address(&DEV, b"DXLYN");
        let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);

        primary_fungible_store::balance(user_addr, dxlyn_coin_metadata)
    }
}