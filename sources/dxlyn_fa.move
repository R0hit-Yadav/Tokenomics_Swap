module FACoin::fa_coin {
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::signer;
    use std::string::{Self, utf8};
    use std::option;
    use std::debug::print;

    const ASSET_SYMBOL: vector<u8> = b"DxlynFA";
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }
    /// Initialize the FA asset and store refs under the metadata object.
    entry fun init_module(admin: &signer) {
        let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"DxlynFA"),
            utf8(ASSET_SYMBOL),
            8,
            utf8(b"http://example.com/favicon.ico"),
            utf8(b"http://example.com"),
        );
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        );
    }
    public fun test_init_module(admin: &signer) {
        init_module(admin);
    }
    /// Return the metadata object for this FA asset.
    public fun get_metadata(admin_addr: address): Object<Metadata> {
        let asset_address = object::create_object_address(&admin_addr, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }
    /// Borrow the refs for mint/transfer/burn, checking admin is the owner.
    inline fun authorized_borrow_refs(owner: &signer, asset: Object<Metadata>): &ManagedFungibleAsset acquires ManagedFungibleAsset 
    {
        assert!(object::is_owner(asset, signer::address_of(owner)), 0x50001);
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }
    /// Deposit FA into a wallet using the transfer ref.
    public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset,transfer_ref: &TransferRef) 
    {
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }
    /// Withdraw FA from a wallet using the transfer ref.
    public fun withdraw<T: key>(store: Object<T>, amount: u64, admin: &signer): FungibleAsset acquires ManagedFungibleAsset {
        let asset = get_metadata(signer::address_of(admin));
        let managed = authorized_borrow_refs(admin, asset);
        fungible_asset::withdraw_with_ref(&managed.transfer_ref, store, amount)
    }
    public entry fun mint(admin: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata(signer::address_of(admin));
        let managed = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed.transfer_ref, to_wallet, fa);
    }
    public fun burn_with_admin<T: key>(admin: &signer, wallet: Object<T>, amount: u64) acquires ManagedFungibleAsset 
    {
        let asset = get_metadata(signer::address_of(admin));
        let managed = authorized_borrow_refs(admin, asset);
        fungible_asset::burn_from(&managed.burn_ref, wallet, amount);
    }
    
    // #[test(admin = @FACoin, user = @0x123)]
    // fun test_fa_mint_withdraw_deposit(admin: &signer, user: &signer) acquires ManagedFungibleAsset {
    //     init_module(admin);
    //     let user_addr = signer::address_of(user);
    //     print(&utf8(b"Testing FA mint, withdraw, and deposit..."));
    //     print(&utf8(b"Minting 100 FA to user..."));
    //     mint(admin, user_addr, 100);
    //     let asset = get_metadata(signer::address_of(admin));
    //     let user_wallet = primary_fungible_store::primary_store(user_addr, asset);
    //     print(&utf8(b"user wallet:"));
    //     print(&user_wallet);
    //     let bal = primary_fungible_store::balance(user_addr, asset);
    //     print(&utf8(b"Checking user balance..."));
    //     print(&bal);
    //     assert!(bal == 100, 100);
    //     // Withdraw 40 FA from user (admin must call)
    //     let fa = withdraw(user_wallet, 40, admin);
    //     print(&utf8(b"Withdrew 40 FA from user, checking balance..."));
    //     let bal1 = primary_fungible_store::balance(user_addr, asset);
    //     print(&bal1);
    //     // Deposit 40 FA back to user
    //     deposit(user_wallet, fa, &authorized_borrow_refs(admin, asset).transfer_ref);
    //     print(&utf8(b"Deposited 40 FA back to user, checking balance..."));
    //     // Check user balance is back to 100
    //     let bal2 = primary_fungible_store::balance(user_addr, asset);
    //     print(&primary_fungible_store::balance(user_addr, asset));
    //     assert!(bal2 == 100, 101);
    // }
}