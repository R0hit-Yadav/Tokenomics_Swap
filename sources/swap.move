// module dxlyn::dexlyn_swap {
//     use std::signer;
//     use std::string::{utf8};
//     use aptos_framework::coin::{Self, BurnCapability, MintCapability, Coin};
//     use aptos_framework::account;
//     use aptos_framework::primary_fungible_store;
//     use aptos_framework::fungible_asset::{Self as fa, FungibleAsset, Metadata, FungibleStore,MintRef,TransferRef,BurnRef};
//     use std::table::{Self as Table, Table};
//     use aptos_framework::object::{Self as Object, Object};
//     use std::option;
//     use std::debug::print;
//     const E_NOT_LOCK: u64 = 1;
//     const E_INSUFFICIENT_BALANCE: u64 = 2;
//     struct DXLYN has store, drop {}
//     const ASSET_SYMBOL: vector<u8> = b"DXLYNFA";
//     #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
//     struct ManagedFungibleAsset has key {
//         mint_ref: MintRef,
//         transfer_ref: TransferRef,
//         burn_ref: BurnRef,
//     }
//     struct Caps has key {
//         dxlyn_mint: MintCapability<DXLYN>,
//         dxlyn_burn: BurnCapability<DXLYN>,
//     }
//     struct LockedFADxlyn has key {
//         locked: Table<address, Object<FungibleStore>>,
//         dxlyn_fa_metadata: Object<Metadata>
//     }
//     /// Initialize the FA asset and store refs under the metadata object.
//     entry fun init_module_fa(admin: &signer) {
//         let constructor_ref = &Object::create_named_object(admin, ASSET_SYMBOL);
//         primary_fungible_store::create_primary_store_enabled_fungible_asset(
//             constructor_ref,
//             option::none(),
//             utf8(b"DXLYNFA Coin"),
//             utf8(ASSET_SYMBOL),
//             8,
//             utf8(b"http://example.com/favicon.ico"),
//             utf8(b"http://example.com"),
//         );
//         let mint_ref = fa::generate_mint_ref(constructor_ref);
//         let burn_ref = fa::generate_burn_ref(constructor_ref);
//         let transfer_ref = fa::generate_transfer_ref(constructor_ref);
//         let metadata_object_signer = Object::generate_signer(constructor_ref);
//         move_to(
//             &metadata_object_signer,
//             ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
//         );
//     }
//     entry fun init_module_coin(admin: &signer) {
//         let (dxlyn_burn, dxlyn_freeze, dxlyn_mint) = coin::initialize<DXLYN>(
//             admin,
//             utf8(b"wDXLYN Coin"),
//             utf8(b"wDXLYN"),
//             8,
//             true
//         );
//         coin::destroy_freeze_cap(dxlyn_freeze);
//         move_to(admin, Caps {
//             dxlyn_mint,
//             dxlyn_burn,
//         });
//         // Get FA constructor and metadata from FACoin
//         let fa_meta = get_metadata(signer::address_of(admin));
//         let table = Table::new<address, Object<FungibleStore>>();
//         move_to(admin, LockedFADxlyn {
//             locked: table,
//             dxlyn_fa_metadata: fa_meta
//         });
//     }
//     // Return the metadata object for this FA asset.
//     public fun get_metadata(admin_addr: address): Object<Metadata> {
//         let asset_address = Object::create_object_address(&admin_addr, ASSET_SYMBOL);
//         Object::address_to_object<Metadata>(asset_address)
//     }
//     // Borrow the refs for mint/transfer/burn, checking admin is the owner.
//     inline fun borrow_refs(owner: &signer, asset: Object<Metadata>): &ManagedFungibleAsset acquires ManagedFungibleAsset 
//     {
//         borrow_global<ManagedFungibleAsset>(Object::object_address(&asset))
//     }
//     // Deposit FA into a wallet using the transfer ref.
//     public fun deposit<T: key>(store: Object<T>,fa: FungibleAsset,transfer_ref: &TransferRef) 
//     {
//         fa::deposit_with_ref(transfer_ref, store, fa);
//     }
//     // Withdraw FA from a wallet using the transfer ref.
//     public fun withdraw<T: key>(store: Object<T>, amount: u64, admin: &signer): FungibleAsset acquires ManagedFungibleAsset {
//         let asset = get_metadata(signer::address_of(admin));
//         let managed = borrow_refs(admin, asset);
//         fa::withdraw_with_ref(&managed.transfer_ref, store, amount)
//     }
//     public entry fun mint(admin: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
//         let asset = get_metadata(signer::address_of(admin));
//         let managed = borrow_refs(admin, asset);
//         let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
//         let fa = fa::mint(&managed.mint_ref, amount);
//         fa::deposit_with_ref(&managed.transfer_ref, to_wallet, fa);
//     }
//     // Swap FA to DXLYN
//     public entry fun swap_fa_to_dxlyn(user: &signer, amount: u64) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         let admin_addr = @dxlyn;
//         let user_addr = signer::address_of(user);
//         // Ensure DXLYN coin registration
//         if (!coin::is_account_registered<DXLYN>(user_addr)) {
//             coin::register<DXLYN>(user);
//         };
//         let caps = borrow_global<Caps>(admin_addr);
//         let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
//         // Ensure user has a primary FA store
//         primary_fungible_store::ensure_primary_store_exists(user_addr, locked_fa.dxlyn_fa_metadata);
//         // Withdraw FA from user and store in a new FungibleStore object
//         let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
//         let fa_refs = borrow_refs(user, locked_fa.dxlyn_fa_metadata);
//         let fa_locked = fa::withdraw_with_ref(&fa_refs.transfer_ref, user_fa_store, amount);
//         if (Table::contains(&locked_fa.locked, user_addr)) 
//         {
//             let locked_store = Table::borrow_mut(&mut locked_fa.locked, user_addr);
//             fa::deposit_with_ref(&fa_refs.transfer_ref, *locked_store, fa_locked);
//         } 
//         else 
//         {
//             // Create new locked store for user
//             let fa_constructor = Object::create_named_object(user, ASSET_SYMBOL);
//             let locked_store = fa::create_store(&fa_constructor, locked_fa.dxlyn_fa_metadata);
//             fa::deposit_with_ref(&fa_refs.transfer_ref, locked_store, fa_locked);
//             Table::add(&mut locked_fa.locked, user_addr, locked_store);
//         };
//         // Mint DXLYN to user
//         let dxlyn_coins = coin::mint<DXLYN>(amount, &caps.dxlyn_mint);
//         coin::deposit<DXLYN>(user_addr, dxlyn_coins);
//     }
//     // Swap DXLYN to FA 
//     public entry fun swap_dxlyn_to_fa(user: &signer, amount: u64) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         let admin_addr = @dxlyn;
//         let user_addr = signer::address_of(user);
//         let caps = borrow_global<Caps>(admin_addr);
//         let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
//         // Check locked FA exists for user
//         assert!(Table::contains(&locked_fa.locked, user_addr), E_NOT_LOCK);
//         let user_locked_store = Table::borrow_mut(&mut locked_fa.locked, user_addr);
//         // Check locked FA balance
//         let locked_balance = fa::balance(*user_locked_store);
//         assert!(locked_balance >= amount, E_INSUFFICIENT_BALANCE);
//         // Burn DXLYN from user
//         let dxlyn = coin::withdraw<DXLYN>(user, amount);
//         coin::burn(dxlyn, &caps.dxlyn_burn);
        
//         // Withdraw FA from locked store
//         let fa_refs = borrow_refs(user, locked_fa.dxlyn_fa_metadata);
//         let fa_to_return = fa::withdraw_with_ref(&fa_refs.transfer_ref, *user_locked_store, amount);
//         // Deposit FA back to user's primary store
//         let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
//         fa::deposit_with_ref(&fa_refs.transfer_ref, user_fa_store, fa_to_return);
//     }
//     #[view]
//     public fun get_locked_fa(user: address): u64 acquires LockedFADxlyn {
//         let admin_addr = @dxlyn;
//         if (exists<LockedFADxlyn>(admin_addr)) {
//             let locked_fa = borrow_global<LockedFADxlyn>(admin_addr);
//             if (Table::contains(&locked_fa.locked, user)) {
//                 let store = Table::borrow(&locked_fa.locked, user);
//                 fa::balance(*store)
//             } else {
//                 0
//             }
//         } else {
//             0
//         }
//     }
//     #[test(admin = @dxlyn, user = @0x123)]
//     #[expected_failure]
//     fun test_swap_fa_to_dxlyn_insufficient_balance(admin: &signer, user: &signer) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         print(&utf8(b""));
//         print(&utf8(b""));
//         // print(&utf8(b""));
//         print(&utf8(b"Expected Failure: Insufficient FA balance for swap..."));
//         init_module_fa(admin);
//         init_module_coin(admin);
//         account::create_account_for_test(@0x1);
//         let aptos_framework_sign = account::create_signer_for_test(@0x1);
//         coin::create_coin_conversion_map(&aptos_framework_sign);
//         let user_addr = signer::address_of(user);
//         let admin_addr = signer::address_of(admin);
//         let asset = get_metadata(signer::address_of(admin));
//         account::create_account_for_test(admin_addr);
//         account::create_account_for_test(user_addr);
//         print(&utf8(b"Minting only 10 FA to user..."));
//         mint(admin, user_addr, 10);
//         print(&primary_fungible_store::balance(user_addr, asset));
//         print(&utf8(b"Attempting to swap 20 FA to DXLYN..."));
//         print(&utf8(b"Failed.."));
//         swap_fa_to_dxlyn(user, 20);
//         print(&get_locked_fa(user_addr));
//     }
//     #[test(admin = @dxlyn, user = @0x123)]
//     #[expected_failure]
//     fun test_swap_dxlyn_to_fa_insufficient_locked(admin: &signer, user: &signer) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b"Expected Failure: Not enough locked FA for user, should fail..."));
//         init_module_fa(admin);
//         init_module_coin(admin);
//         account::create_account_for_test(@0x1);
//         let aptos_framework_sign = account::create_signer_for_test(@0x1);
//         coin::create_coin_conversion_map(&aptos_framework_sign);
//         let user_addr = signer::address_of(user);
//         let admin_addr = signer::address_of(admin);
//         account::create_account_for_test(admin_addr);
//         account::create_account_for_test(user_addr);
//         print(&utf8(b"Minting 50 FA to user..."));
//         mint(admin, user_addr, 50);
//         print(&utf8(b"Swapping 30 FA to DXLYN..."));
//         swap_fa_to_dxlyn(user, 30);
//         print(&get_locked_fa(user_addr));
//         print(&utf8(b"Attempting to swap 40 DXLYN back to FA..."));
//         print(&utf8(b"Failed.."));
        
//         swap_dxlyn_to_fa(user, 40);
//         print(&get_locked_fa(user_addr));
//     }
//     #[test(admin = @dxlyn, user = @0x123)]
//     #[expected_failure]
//     fun test_swap_dxlyn_to_fa_no_locked(admin: &signer, user: &signer) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b"Expacted Failure: No locked FA for user, should fail..."));
//         init_module_fa(admin);
//         init_module_coin(admin);
//         print(&utf8(b"Testing swap DXLYN to FA with no locked FA..."));
//         print(&utf8(b"Failed.."));
//         swap_dxlyn_to_fa(user, 10);
//     }
//     #[test(admin = @dxlyn, user = @0x123)]
//     fun test_swap_fa_to_dxlyn_and_back(admin: &signer, user: &signer) acquires Caps, LockedFADxlyn, ManagedFungibleAsset {
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b"Testing swap FA to DXLYN and back..."));
        
//         init_module_fa(admin);
//         init_module_coin(admin);
//         account::create_account_for_test(@0x1);
//         let aptos_framework_sign = account::create_signer_for_test(@0x1);
//         coin::create_coin_conversion_map(&aptos_framework_sign);
//         let user_addr = signer::address_of(user);
//         let admin_addr = signer::address_of(admin);
//         account::create_account_for_test(admin_addr);
//         account::create_account_for_test(user_addr);
//         coin::register<DXLYN>(user);
//         print(&utf8(b"Minting 100 FA to user..."));
//         // Mint FA to user
//         mint(admin, user_addr, 100);
//         // User swaps 40 FA for 40 DXLYN
//         print(&utf8(b"Swapping 40 FA to DXLYN..."));
//         swap_fa_to_dxlyn(user, 40);
//         print(&utf8(b"Checking lock FA balance..."));
//         print(&get_locked_fa(user_addr));
//         // Check locked FA
//         assert!(get_locked_fa(user_addr) == 40, E_INSUFFICIENT_BALANCE);
//         // Check user DXLYN balance
//         print(&utf8(b"Checking user DXLYN balance..."));
//         let dxlyn_balance = coin::balance<DXLYN>(user_addr);
//         print(&dxlyn_balance);
//         assert!(dxlyn_balance == 40, E_INSUFFICIENT_BALANCE);
//         // User swaps 20 DXLYN back for 20 FA
//         print(&utf8(b"Swapping 20 DXLYN back to FA..."));
//         swap_dxlyn_to_fa(user, 20);
//         // Check locked FA reduced
//         print(&utf8(b"Checking locked FA after swap back..."));
//         print(&get_locked_fa(user_addr));
//         assert!(get_locked_fa(user_addr) == 20, E_INSUFFICIENT_BALANCE);
//         // Check user DXLYN balance reduced
//         print(&utf8(b"Checking user DXLYN balance after swap back..."));
//         let dxlyn_balance2 = aptos_framework::coin::balance<DXLYN>(user_addr);
//         print(&dxlyn_balance2);
//         assert!(dxlyn_balance2 == 20, E_INSUFFICIENT_BALANCE);
//         // Check user FA balance increased by 20 (should be 80: 100 - 40 + 20)
//         print(&utf8(b"Checking user FA balance after swap back..."));
//         let fa_meta = get_metadata(signer::address_of(admin));
//         let fa_balance = aptos_framework::primary_fungible_store::balance(user_addr, fa_meta);
//         print(&fa_balance);
//         assert!(fa_balance == 80, E_INSUFFICIENT_BALANCE);
//     }
//     // FA ccoin test
//     #[test(admin = @FACoin, user = @0x123)]
//     fun test_fa_mint_withdraw_deposit(admin: &signer, user: &signer) acquires ManagedFungibleAsset 
//     {
//         print(&utf8(b""));
//         print(&utf8(b""));
//         print(&utf8(b""));
//         init_module_fa(admin);
//         let user_addr = signer::address_of(user);
//         print(&utf8(b"Testing FA mint, withdraw, and deposit..."));
//         print(&utf8(b"Minting 100 FA to user..."));
//         mint(admin, user_addr, 100);
//         let asset = get_metadata(signer::address_of(admin));
//         let user_wallet = primary_fungible_store::primary_store(user_addr, asset);
//         print(&utf8(b"user wallet:"));
//         print(&user_wallet);
//         let bal = primary_fungible_store::balance(user_addr, asset);
//         print(&utf8(b"Checking user balance..."));
//         print(&bal);
//         assert!(bal == 100, E_INSUFFICIENT_BALANCE);
//         // Withdraw 40 FA from user (admin must call)
//         let fa = withdraw(user_wallet, 40, admin);
//         print(&utf8(b"Withdrew 40 FA from user, checking balance..."));
//         let bal1 = primary_fungible_store::balance(user_addr, asset);
//         print(&bal1);
//         // Deposit 40 FA back to user
//         deposit(user_wallet, fa, &borrow_refs(admin, asset).transfer_ref);
//         print(&utf8(b"Deposited 40 FA back to user, checking balance..."));
//         // Check user balance is back to 100
//         let bal2 = primary_fungible_store::balance(user_addr, asset);
//         print(&primary_fungible_store::balance(user_addr, asset));
//         assert!(bal2 == 100, E_INSUFFICIENT_BALANCE);
        
//     }
// }