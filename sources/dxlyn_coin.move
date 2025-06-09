// module dxlyn::dxlyn_coin {
//     use std::signer;
//     use std::string::utf8;

//     use aptos_framework::coin::{Self, BurnCapability, MintCapability};
//     use aptos_framework::aptos_account;
//     use aptos_framework::timestamp;

//     #[test_only]
//     use std::option;
//     #[test_only]
//     use std::signer::address_of;
//     #[test_only]
//     use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
//     #[test_only]
//     use aptos_framework::object;
//     #[test_only]
//     use aptos_framework::primary_fungible_store;

//     struct DXLYN {}

//     const WEEK: u64 = 7 * 86400;
//     const DEV: address = @dev;


//     /// Storing mint/burn capabilities for coins under user account.
//     struct Caps<phantom CoinType> has key {
//         mint: MintCapability<CoinType>,
//         burn: BurnCapability<CoinType>,
//     }

//     struct ActivePeriod has key {
//         period: u64
//     }

//     /// Initialize module - as initialize dxlyn token
//     fun init_module(token_admin: &signer) {
//         let (dxlyn_b, dxlyn_f, dxlyn_m) =
//             coin::initialize<DXLYN>(token_admin,
//                 utf8(b"DXLYN Coin"), utf8(b"DXLYN"), 8, true);

//         coin::destroy_freeze_cap(dxlyn_f);
//         move_to(token_admin, Caps<DXLYN> { mint: dxlyn_m, burn: dxlyn_b });
//     }

//     /// Mints new coin `CoinType` on account `acc_addr`.
//     public entry fun mint_coin<CoinType>(token_admin: &signer, acc_addr: address, amount: u64) acquires Caps {
//         let token_admin_addr = signer::address_of(token_admin);
//         let caps = borrow_global<Caps<CoinType>>(token_admin_addr);
//         let coins = coin::mint<CoinType>(amount, &caps.mint);
//         aptos_account::deposit_coins<CoinType>(acc_addr, coins);
//     }


//     public fun initialize(sender: &signer, period: u64) {
//         move_to(sender, ActivePeriod { period });
//     }

//     public fun set_active_period(period: u64) acquires ActivePeriod {
//         let account = @dev;
//         let active_period = borrow_global_mut<ActivePeriod>(account);
//         active_period.period = period;
//     }

//     #[view]
//     public fun active_period(): u64 acquires ActivePeriod {
//         let account = @dev;
//         borrow_global<ActivePeriod>(account).period
//     }

//     public fun update_period() acquires ActivePeriod {
//         let account = @dev;
//         let active_period = borrow_global_mut<ActivePeriod>(account);
//         let current_time = timestamp::now_seconds();
//         if (current_time >= active_period.period + WEEK) {x
//             active_period.period = (current_time / WEEK) * WEEK;
//         };
//     }


//     #[test_only]
//     struct ManagedFungibleAsset has key {
//         mint_ref: MintRef,
//     }


//     #[test_only]
//     public fun init_coin(account: &signer) {
//         let constructor_ref = &object::create_named_object(account, b"DXLYN");

//         primary_fungible_store::create_primary_store_enabled_fungible_asset(
//             constructor_ref,
//             option::none(),
//             utf8(b"DXLYN Coin"), /* name */
//             utf8(b"DXLYN"), /* symbol */
//             8, /* decimals */
//             utf8(b"http://example.com/favicon.ico"), /* icon */
//             utf8(b"http://example.com"), /* project */
//         );

//         let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);

//         let siger = object::generate_signer(constructor_ref);

//         move_to(&siger, ManagedFungibleAsset { mint_ref });

//         let active_period = ((timestamp::now_seconds(
//         ) + (2 * WEEK)) / WEEK) * WEEK; // Mimics MinterUpgradeable.initialize
//         initialize(account, active_period);
//     }

//     #[test_only]
//     public fun init_usdt_coin(account: &signer) {
//         let constructor_ref = &object::create_named_object(account, b"USDT");

//         primary_fungible_store::create_primary_store_enabled_fungible_asset(
//             constructor_ref,
//             option::none(),
//             utf8(b"USDT Coin"), /* name */
//             utf8(b"USDT"), /* symbol */
//             8, /* decimals */
//             utf8(b"http://example.com/favicon.ico"), /* icon */
//             utf8(b"http://example.com"), /* project */
//         );

//         let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);

//         let siger = object::generate_signer(constructor_ref);

//         move_to(&siger, ManagedFungibleAsset { mint_ref });
//     }

//     #[test_only]
//     public fun register_and_mint(account: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
//         let object_add = object::create_object_address(&address_of(account), b"DXLYN");

//         let cap = borrow_global<ManagedFungibleAsset>(object_add);

//         let coin = fungible_asset::mint(&cap.mint_ref, amount);

//         let asset = object::address_to_object<Metadata>(object_add);

//         let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);

//         fungible_asset::deposit(to_wallet, coin);
//     }

//     #[test_only]
//     public fun register_and_mint_usdt(account: &signer, to: address, amount: u64) acquires ManagedFungibleAsset {
//         let object_add = object::create_object_address(&address_of(account), b"USDT");

//         let cap = borrow_global<ManagedFungibleAsset>(object_add);

//         let coin = fungible_asset::mint(&cap.mint_ref, amount);

//         let asset = object::address_to_object<Metadata>(object_add);

//         let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);

//         fungible_asset::deposit(to_wallet, coin);
//     }

//     #[test_only]
//     public fun get_usdt_metadata(account: &signer): address {
//         object::create_object_address(&address_of(account), b"USDT")
//     }

//     #[test_only]
//     public fun get_dxlyn_metadata(account: &signer): address {
//         object::create_object_address(&address_of(account), b"DXLYN")
//     }

//     #[test_only]
//     public fun get_user_usdt_balance(user_addr: address): u64 {
//         //usdt coin metadata
//         let usdt_coin_address = object::create_object_address(&DEV, b"USDT");
//         let usdt_coin_metadata = object::address_to_object<Metadata>(usdt_coin_address);

//         primary_fungible_store::balance(user_addr, usdt_coin_metadata)
//     }

//     #[test_only]
//     public fun get_user_dxlyn_balance(user_addr: address): u64 {
//         //usdt coin metadata
//         let dxlyn_coin_address = object::create_object_address(&DEV, b"DXLYN");
//         let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);

//         primary_fungible_store::balance(user_addr, dxlyn_coin_metadata)
//     }
// }