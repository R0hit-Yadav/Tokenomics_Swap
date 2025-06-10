// module dxlyn::wdxlyn_coin {
//     use std::signer;
//     use std::string::utf8;
//     use aptos_framework::coin::{Self, BurnCapability, MintCapability};

//     struct DXLYN has store, drop {}  // <-- Changed name to match usage

//     const DEV: address = @dev;

//     struct Caps has key {
//         mint: MintCapability<DXLYN>,
//         burn: BurnCapability<DXLYN>,
//     }

//     public fun init_module(admin: &signer) {
//         let (burn_cap, freeze_cap, mint_cap) = coin::initialize<DXLYN>(
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

//     // Return references instead of moving capabilities
//     public fun borrow_mint_cap(admin: &signer): &MintCapability<DXLYN> acquires Caps {
//         &borrow_global<Caps>(signer::address_of(admin)).mint
//     }

//     public fun borrow_burn_cap(admin: &signer): &BurnCapability<DXLYN> acquires Caps {
//         &borrow_global<Caps>(signer::address_of(admin)).burn
//     }
// }
