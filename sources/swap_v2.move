module dxlyn::dxlyn_swap {
    use std::signer;
    use std::string::{utf8};
    use aptos_framework::coin::{Self, BurnCapability, MintCapability, Coin};
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata, FungibleStore,MintRef};
    use std::table::{Self,Table};
    use aptos_framework::object::{Self,Object};
    use std::option;
    use std::debug::print;
    use dxlyn::wdxlyn_coin;

    
    const DEV: address = @dev;

    const DXLYN_FA_SEED: vector<u8> = b"DXLYN";

    /// insufficient FA balance
    const E_INSUFFICIENT_FA_BALANCE: u64 = 100;
    /// NO locked FA for user
    const E_NO_LOCKED_FA: u64 = 101;
    /// insufficient locked FA balance
    const E_INSUFFICIENT_LOCKED_FA: u64 = 102;
    /// insufficient DXLYN balance
    const E_INSUFFICIENT_DXLYN: u64 = 103;

    /// not admin 
    const E_NOT_ADMIN: u64 = 1000;

    struct LockedFADxlyn has key {
        locked: Table<address, Object<FungibleStore>>,
        dxlyn_fa_metadata: Object<Metadata>
    }

    entry fun init_module(admin: &signer) 
    {
        assert!(signer::address_of(admin) == DEV, 1000);
        wdxlyn_coin::init_module_test(admin);

        // Initialize the LockedFADxlyn resource
        let dxlyn_coin_address = object::create_object_address(&DEV, DXLYN_FA_SEED);
        let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);

        let table = table::new<address, Object<FungibleStore>>();
        move_to(admin, LockedFADxlyn {
            locked: table,
            dxlyn_fa_metadata: dxlyn_coin_metadata
        });
    }
    
    public entry fun init_module_test_swap(admin: &signer) {
        init_module(admin);
    }

    // Swap FA to DXLYN 
    public entry fun swap_fa_to_dxlyn(user: &signer, amount: u64) acquires LockedFADxlyn {
        let admin_addr = @dev;
        let user_addr = signer::address_of(user);

        // DXLYN coin registration
        if (!coin::is_account_registered<wdxlyn_coin::DXLYN>(user_addr)) {
            coin::register<wdxlyn_coin::DXLYN>(user);
        };
 
        let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);

        // check FA balance of user 
        assert!(primary_fungible_store::balance(user_addr, locked_fa.dxlyn_fa_metadata) >= amount, E_INSUFFICIENT_FA_BALANCE);

        // FA metadata from the LockedFADxlyn resource
        primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);

        // Withdraw FA from user and store in a new FungibleStore object
        let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
        let fa_locked = fungible_asset::withdraw(user, user_fa_store, amount);

        if (locked_fa.locked.contains(user_addr)) {
            // deposit into existing locked store
            let locked_store = locked_fa.locked.borrow_mut(user_addr);
            fungible_asset::deposit(*locked_store, fa_locked);
        } else {
            // Create new locked store using the same FA object pattern
            let fa_constructor = object::create_named_object(user, DXLYN_FA_SEED);
            let locked_store = fungible_asset::create_store(&fa_constructor, locked_fa.dxlyn_fa_metadata);
            fungible_asset::deposit(locked_store, fa_locked);
            locked_fa.locked.add(user_addr, locked_store);

            // primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);
            // let new_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
            // fungible_asset::deposit(new_store, fa_locked);
            // locked_fa.locked.add(user_addr, new_store);
        };

        // Mint DXLYN to user
        let dxlyn_coins = wdxlyn_coin::mint_dxlyn(admin_addr, amount);
        coin::deposit<wdxlyn_coin::DXLYN>(user_addr, dxlyn_coins);
    }

    // Swap DXLYN to FA
    public entry fun swap_dxlyn_to_fa(user: &signer, amount: u64) acquires LockedFADxlyn {
        let admin_addr = @dev;
        let user_addr = signer::address_of(user);
        let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);

        // Check locked FA exists for user
        assert!(locked_fa.locked.contains(user_addr), E_NO_LOCKED_FA);
        let user_locked_store = locked_fa.locked.borrow_mut(user_addr);

        // Check locked FA balance
        let locked_balance = fungible_asset::balance(*user_locked_store);
        assert!(locked_balance >= amount, E_INSUFFICIENT_LOCKED_FA);

        // check user has enough DXLYN
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) >= amount, E_INSUFFICIENT_DXLYN);
        
        // Burn DXLYN from user
        let dxlyn = coin::withdraw<wdxlyn_coin::DXLYN>(user, amount);
        wdxlyn_coin::burn_dxlyn(admin_addr, dxlyn);

        // Withdraw FA from locked store
        let fa_to_return = fungible_asset::withdraw(user, *user_locked_store, amount);

        // Deposit FA back to user's primary store
        let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
        fungible_asset::deposit(user_fa_store, fa_to_return);
    }

    #[view]
    public fun get_locked_fa(user: address): u64 acquires LockedFADxlyn {
        let admin_addr = @dev;
        if (exists<LockedFADxlyn>(admin_addr)) {
            let locked_fa = borrow_global<LockedFADxlyn>(admin_addr);
            if (locked_fa.locked.contains(user)) {
                let store = locked_fa.locked.borrow(user);
                fungible_asset::balance(*store)
            } else {
                0
            }
        } else {
            0
        }
    }
}
