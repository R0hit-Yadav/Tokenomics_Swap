// 1. wdxlyn_coin.move (New File)
// move
// module dxlyn::wdxlyn_coin {
//     use std::signer;
//     use std::string::utf8;
//     use aptos_framework::coin::{Self, BurnCapability, MintCapability};

//     struct wDXLYN has store, drop {}

//     const DEV: address = @dev;

//     /// Stores mint/burn capabilities for wDXLYN coin
//     struct Caps has key {
//         mint: MintCapability<wDXLYN>,
//         burn: BurnCapability<wDXLYN>,
//     }

//     /// Initialize wDXLYN coin (called once by admin)
//     public fun init_module(admin: &signer) {
//         let (burn_cap, freeze_cap, mint_cap) = coin::initialize<wDXLYN>(
//             admin,
//             utf8(b"wDXLYN Coin"),
//             utf8(b"wDXLYN"),
//             8,
//             true
//         );
        
//         coin::destroy_freeze_cap(freeze_cap);
//         move_to(admin, Caps {
//             mint: mint_cap,
//             burn: burn_cap
//         });
//     }

//     /// Get mint capability (for swap contract)
//     public fun get_mint_cap(admin: address): MintCapability<wDXLYN> acquires Caps {
//         borrow_global<Caps>(admin).mint
//     }

//     /// Get burn capability (for swap contract)
//     public fun get_burn_cap(admin: address): BurnCapability<wDXLYN> acquires Caps {
//         borrow_global<Caps>(admin).burn
//     }
// }





// 2. Updated swap.move
// move
// module dxlyn::dxlyn_swap {
//     use std::signer;
//     use std::string::utf8;
//     use aptos_framework::coin::{Self, Coin};
//     use aptos_framework::primary_fungible_store;
//     use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};
//     use aptos_framework::object::{Self, Object};
//     use std::table::{Self, Table};

//     use dxlyn::wdxlyn_coin; // Import from new file

//     const DEV: address = @dev;
//     const DXLYN_FA_SEED: vector<u8> = b"DXLYN";

//     struct LockedFADxlyn has key {
//         locked: Table<address, Object<FungibleStore>>,
//         dxlyn_fa_metadata: Object<Metadata>
//     }

//     // ====== Initialization ======
//     public entry fun init_module(admin: &signer) {
//         // Initialize wDXLYN coin (delegated to wdxlyn_coin.move)
//         wdxlyn_coin::init_module(admin);

//         // Initialize FA metadata
//         let dxlyn_coin_address = object::create_object_address(&DEV, DXLYN_FA_SEED);
//         let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);
        
//         move_to(admin, LockedFADxlyn {
//             locked: table::new(),
//             dxlyn_fa_metadata: dxlyn_coin_metadata
//         });
//     }

//     // ====== Swap Functions ======
//     public entry fun swap_fa_to_dxlyn(
//         user: &signer,
//         amount: u64
//     ) acquires LockedFADxlyn {
//         let admin_addr = @dev;
//         let user_addr = signer::address_of(user);

//         // Ensure wDXLYN is registered
//         if (!coin::is_account_registered<wdxlyn_coin::wDXLYN>(user_addr)) {
//             coin::register<wdxlyn_coin::wDXLYN>(user);
//         };

//         let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
//         let mint_cap = wdxlyn_coin::get_mint_cap(admin_addr);

//         // Lock FA
//         let user_fa_store = primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata);
//         let fa_locked = fungible_asset::withdraw(user, user_fa_store, amount);

//         if (!table::contains(&locked_fa.locked, user_addr)) {
//             let store = fungible_asset::create_store(
//                 &object::create_named_object(user, DXLYN_FA_SEED),
//                 locked_fa.dxlyn_fa_metadata
//             );
//             table::add(&mut locked_fa.locked, user_addr, store);
//         };
//         fungible_asset::deposit(*table::borrow_mut(&mut locked_fa.locked, user_addr), fa_locked);

//         // Mint wDXLYN
//         coin::deposit(user_addr, coin::mint<wdxlyn_coin::wDXLYN>(amount, &mint_cap));
//     }

//     public entry fun swap_dxlyn_to_fa(
//         user: &signer,
//         amount: u64
//     ) acquires LockedFADxlyn {
//         let admin_addr = @dev;
//         let user_addr = signer::address_of(user);
//         let locked_fa = borrow_global_mut<LockedFADxlyn>(admin_addr);
//         let burn_cap = wdxlyn_coin::get_burn_cap(admin_addr);

//         // Verify locked balance
//         assert!(
//             table::contains(&locked_fa.locked, user_addr) &&
//             fungible_asset::balance(*table::borrow(&locked_fa.locked, user_addr)) >= amount,
//             102
//         );

//         // Burn wDXLYN
//         coin::burn(coin::withdraw<wdxlyn_coin::wDXLYN>(user, amount), &burn_cap);

//         // Unlock FA
//         let fa_to_return = fungible_asset::withdraw(
//             user,
//             *table::borrow_mut(&mut locked_fa.locked, user_addr),
//             amount
//         );
//         fungible_asset::deposit(
//             primary_fungible_store::primary_store(user_addr, locked_fa.dxlyn_fa_metadata),
//             fa_to_return
//         );
//     }

//     // ====== View Functions ======
//     public fun get_locked_fa(user: address): u64 acquires LockedFADxlyn {
//         if (exists<LockedFADxlyn>(@dev)) {
//             let locked_fa = borrow_global<LockedFADxlyn>(@dev);
//             if (table::contains(&locked_fa.locked, user)) {
//                 fungible_asset::balance(*table::borrow(&locked_fa.locked, user))
//             } else { 0 }
//         } else { 0 }
//     }
// }