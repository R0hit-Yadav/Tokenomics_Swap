module dxlyn::dxlyn_swap {
    use std::signer;
    use std::string;
    use supra_framework::coin;
    use supra_framework::primary_fungible_store;
    use supra_framework::fungible_asset;
    use supra_framework::fungible_asset::{Metadata, FungibleStore};
    use std::table::{Self,Table};
    use supra_framework::object::{Self,Object};
    use supra_framework::event;
    use dxlyn::wdxlyn_coin;

    
    const DEV: address = @dev;

    const DXLYN_FA_SEED: vector<u8> = b"DXLYN";

    /// not admin 
    const ERROR_NOT_ADMIN: u64 = 100;
    /// insufficient FA balance
    const ERROR_INSUFFICIENT_FA_BALANCE: u64 = 101;
    /// NO locked FA for user
    const ERROR_NO_LOCKED_FA: u64 = 102;
    /// insufficient locked FA balance
    const ERROR_INSUFFICIENT_LOCKED_FA: u64 = 103;
    /// insufficient DXLYN balance
    const ERROR_INSUFFICIENT_DXLYN: u64 = 104;
    /// already initialized
    const ERROR_ALREADY_INITIALIZED: u64 = 105;


    #[event]
    struct SwapEvent has store, drop, copy {
        user: address,
        amount: u64,
        direction: u8, // 0 = FA->DXLYN, 1 = DXLYN->FA
    }

    struct LockedFADxlyn has key {
        locked: Table<address, Object<FungibleStore>>,
        dxlyn_fa_metadata: Object<Metadata>,
    }

    fun init_module(admin: &signer) 
    {
        assert!(signer::address_of(admin) == DEV, ERROR_NOT_ADMIN);
        assert!(!exists<LockedFADxlyn>(signer::address_of(admin)), ERROR_ALREADY_INITIALIZED);
        
        wdxlyn_coin::init_module_wdxlyn(admin);

        // Initialize the LockedFADxlyn resource
        let dxlyn_coin_address = object::create_object_address(&DEV, DXLYN_FA_SEED);
        let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);

        let table = table::new<address, Object<FungibleStore>>();
        move_to(admin, LockedFADxlyn {
            locked: table,
            dxlyn_fa_metadata: dxlyn_coin_metadata,
        });
    }
    
    #[test_only]
    public fun init_module_test_swap(admin: &signer) {
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
        assert!(primary_fungible_store::balance(user_addr, locked_fa.dxlyn_fa_metadata) >= amount, ERROR_INSUFFICIENT_FA_BALANCE);

        // Withdraw FA from user and store in a new FungibleStore object
        let user_fa_store = primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);
        let fa_locked = fungible_asset::withdraw(user, user_fa_store, amount);

        if (table::contains(&locked_fa.locked, user_addr)) {
            // deposit into existing locked store
            let locked_store = table::borrow_mut(&mut locked_fa.locked, user_addr);
            fungible_asset::deposit(*locked_store, fa_locked);
        } else {

            // Create new locked store using the same FA object pattern
            let fa_constructor = object::create_named_object(user, DXLYN_FA_SEED);
            let locked_store = fungible_asset::create_store(&fa_constructor, locked_fa.dxlyn_fa_metadata);
            fungible_asset::deposit(locked_store, fa_locked);
            table::add(&mut locked_fa.locked, user_addr, locked_store);


            // primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);
            // let new_store = primary_fungible_store::create_primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
            // fungible_asset::deposit(new_store, fa_locked);
            // table::add(&mut locked_fa.locked, user_addr, new_store);
        };

        // Mint DXLYN to user
        let dxlyn_coins = wdxlyn_coin::mint_dxlyn(admin_addr, amount);
        coin::deposit<wdxlyn_coin::DXLYN>(user_addr, dxlyn_coins);

        // Emit swap event
        event::emit(SwapEvent {
            user: user_addr,
            amount,
            direction: 0,
        });
    }

    // Swap DXLYN to FA
    public entry fun swap_dxlyn_to_fa(user: &signer, amount: u64) acquires LockedFADxlyn {
        let admin_addr = @dev;
        let user_addr = signer::address_of(user);
        let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);

        // Check locked FA exists for user
        assert!(table::contains(&locked_fa.locked, user_addr), ERROR_NO_LOCKED_FA);
        let user_locked_store = table::borrow_mut(&mut locked_fa.locked, user_addr);

        // Check locked FA balance
        let locked_balance = fungible_asset::balance(*user_locked_store);
        assert!(locked_balance >= amount, ERROR_INSUFFICIENT_LOCKED_FA);

        // check user has enough DXLYN
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) >= amount, ERROR_INSUFFICIENT_DXLYN);
        
        // Burn DXLYN from user
        let dxlyn = coin::withdraw<wdxlyn_coin::DXLYN>(user, amount);
        wdxlyn_coin::burn_dxlyn(admin_addr, dxlyn);

        // Withdraw FA from locked store
        let fa_to_return = fungible_asset::withdraw(user, *user_locked_store, amount);

        if (fungible_asset::balance(*user_locked_store) == 0) 
        {
            table::remove(&mut locked_fa.locked, user_addr);
        };

        // Deposit FA back to user's primary store
        let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
        fungible_asset::deposit(user_fa_store, fa_to_return);

        // Emit swap event
        event::emit(SwapEvent {
            user: user_addr,
            amount,
            direction: 1,
        });
    }

    #[view]
    public fun get_locked_fa(user: address): u64 acquires LockedFADxlyn {
        let admin_addr = @dev;
        if (exists<LockedFADxlyn>(admin_addr)) {
            let locked_fa = borrow_global<LockedFADxlyn>(admin_addr);
            if (table::contains(&locked_fa.locked, user)) {
                let store = table::borrow(&locked_fa.locked, user);
                fungible_asset::balance(*store)
            } else {
                0
            }
        } else {
            0
        }
    }
}
