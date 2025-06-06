module dxlyn::dexlyn_swap {
    use std::signer;
    use std::string::{utf8};
    use aptos_framework::coin::{Self, BurnCapability, MintCapability, Coin};
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self as fa, Metadata, FungibleStore};
    use std::table::{Self as Table, Table};
    use aptos_framework::object::{Self as Object, Object};
    use FACoin::fa_coin; 
    use std::option;
    use std::debug::print;
    struct DXLYN has store, drop {}
    
    const ASSET_SYMBOL: vector<u8> = b"DxlynFA";
    struct Caps has key {
        dxlyn_mint: MintCapability<DXLYN>,
        dxlyn_burn: BurnCapability<DXLYN>,
    }
    struct LockedFADxlyn has key {
        locked: Table<address, Object<FungibleStore>>,
        dxlyn_fa_metadata: Object<Metadata>
    }
    
    entry fun init_module(admin: &signer) {
        let (dxlyn_burn, dxlyn_freeze, dxlyn_mint) = coin::initialize<DXLYN>(
            admin,
            utf8(b"wDXLYN Coin"),
            utf8(b"wDXLYN"),
            8,
            true
        );
        coin::destroy_freeze_cap(dxlyn_freeze);
        move_to(admin, Caps {
            dxlyn_mint,
            dxlyn_burn,
        });
        // Get FA constructor and metadata from FACoin
        let fa_meta = fa_coin::get_metadata(signer::address_of(admin));
        let table = Table::new<address, Object<FungibleStore>>();
        move_to(admin, LockedFADxlyn {
            locked: table,
            dxlyn_fa_metadata: fa_meta
        });
    }
    // Swap FA to DXLYN (user only, no admin needed)
    public entry fun swap_fa_to_dxlyn(user: &signer, amount: u64) acquires Caps, LockedFADxlyn {
        let admin_addr = @dxlyn;
        let user_addr = signer::address_of(user);
        // Ensure DXLYN coin registration
        if (!coin::is_account_registered<DXLYN>(user_addr)) {
            coin::register<DXLYN>(user);
        };
        let caps = borrow_global<Caps>(admin_addr);
        let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
        // Ensure user has a primary FA store
        primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);
        // Withdraw FA from user and store in a new FungibleStore object
        let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
        let fa_locked = fa::withdraw(user,user_fa_store, amount);
        if (Table::contains(&locked_fa.locked, user_addr)) {
        // Deposit into existing locked store
        let locked_store = Table::borrow_mut(&mut locked_fa.locked, user_addr);
        fa::deposit(*locked_store, fa_locked);
        } else {
            // Create new locked store
            let fa_constructor = Object::create_named_object(user, ASSET_SYMBOL);
            let locked_store = fa::create_store(&fa_constructor, locked_fa.dxlyn_fa_metadata);
            fa::deposit(locked_store, fa_locked);
            Table::add(&mut locked_fa.locked, user_addr, locked_store);
        };
            // Mint DXLYN to user
        let dxlyn_coins = coin::mint<DXLYN>(amount, &caps.dxlyn_mint);
        coin::deposit<DXLYN>(user_addr, dxlyn_coins);
    }
    // Swap DXLYN to FA (user only)
    public entry fun swap_dxlyn_to_fa(user: &signer, amount: u64) acquires Caps, LockedFADxlyn {
        let admin_addr = @dxlyn;
        let user_addr = signer::address_of(user);
        let caps = borrow_global<Caps>(admin_addr);
        let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
        // Check locked FA exists for user
        assert!(Table::contains(&locked_fa.locked, user_addr), 101);
        let user_locked_store = Table::borrow_mut(&mut locked_fa.locked, user_addr);
        // Check locked FA balance
        let locked_balance = primary_fungible_store::balance(Object::object_address(user_locked_store), locked_fa.dxlyn_fa_metadata);
        assert!(locked_balance >= amount, 102);
        // Burn DXLYN from user
        let dxlyn = coin::withdraw<DXLYN>(user, amount);
        coin::burn(dxlyn, &caps.dxlyn_burn);
        
        // Withdraw FA from locked store
        let fa_to_return = fa::withdraw(user,*user_locked_store, amount);
        // Deposit FA back to user's primary store
        let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
        fa::deposit(user_fa_store, fa_to_return);
    }
    public fun get_locked_fa(user: address): u64 acquires LockedFADxlyn {
        let admin_addr = @dxlyn;
        if (exists<LockedFADxlyn>(admin_addr)) {
            let locked_fa = borrow_global<LockedFADxlyn>(admin_addr);
            if (Table::contains(&locked_fa.locked, user)) {
                let store = Table::borrow(&locked_fa.locked, user);
                primary_fungible_store::balance(Object::object_address(store), locked_fa.dxlyn_fa_metadata)
            } else {
                0
            }
        } else {
            0
        }
    }
    #[test(admin = @dxlyn, user = @0x123)]
    fun test_swap_fa_to_dxlyn_and_back(admin: &signer, user: &signer) acquires Caps, LockedFADxlyn {
        print(&utf8(b"Testing swap FA to DXLYN and back..."));
        
        FACoin::fa_coin::test_init_module(admin);
        init_module(admin);
        account::create_account_for_test(@0x1);
        let aptos_framework_sign = account::create_signer_for_test(@0x1);
        coin::create_coin_conversion_map(&aptos_framework_sign);
        let user_addr = signer::address_of(user);
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        coin::register<DXLYN>(user);
        print(&utf8(b"Minting 100 FA to user..."));
        // Mint FA to user
        FACoin::fa_coin::mint(admin, user_addr, 100);
        // User swaps 40 FA for 40 DXLYN
        print(&utf8(b"Swapping 40 FA to DXLYN..."));
        swap_fa_to_dxlyn(user, 40);
        print(&utf8(b"Checking lock FA balance..."));
        print(&get_locked_fa(user_addr));
        // Check locked FA
        assert!(get_locked_fa(user_addr) == 40, 100);
        // Check user DXLYN balance
        print(&utf8(b"Checking user DXLYN balance..."));
        let dxlyn_balance = coin::balance<DXLYN>(user_addr);
        print(&dxlyn_balance);
        assert!(dxlyn_balance == 40, 101);
        // User swaps 20 DXLYN back for 20 FA
        print(&utf8(b"Swapping 20 DXLYN back to FA..."));
        swap_dxlyn_to_fa(user, 20);
        // Check locked FA reduced
        print(&utf8(b"Checking locked FA after swap back..."));
        print(&get_locked_fa(user_addr));
        assert!(get_locked_fa(user_addr) == 20, 102);
        // Check user DXLYN balance reduced
        print(&utf8(b"Checking user DXLYN balance after swap back..."));
        let dxlyn_balance2 = aptos_framework::coin::balance<DXLYN>(user_addr);
        print(&dxlyn_balance2);
        assert!(dxlyn_balance2 == 20, 103);
        // Check user FA balance increased by 20 (should be 80: 100 - 40 + 20)
        print(&utf8(b"Checking user FA balance after swap back..."));
        let fa_meta = FACoin::fa_coin::get_metadata(signer::address_of(admin));
        let fa_balance = aptos_framework::primary_fungible_store::balance(user_addr, fa_meta);
        print(&fa_balance);
        assert!(fa_balance == 80, 104);
    }
}