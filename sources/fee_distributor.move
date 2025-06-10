// module fee_distributor::fee_distributor {

//     use std::signer::address_of;
//     use std::vector;
//     use aptos_std::math64::max;
//     use aptos_std::table::{Self, Table};

//     use supra_framework::coin;
//     use supra_framework::event;
//     use supra_framework::fungible_asset;
//     use supra_framework::fungible_asset::{FungibleStore, Metadata};
//     use supra_framework::object;
//     use supra_framework::object::{ExtendRef, Object};
//     use supra_framework::primary_fungible_store;
//     use supra_framework::supra_account;
//     use supra_framework::timestamp;

//     use dexlyn_tokenomics::voting_escrow;

//     // Configuration constants for the fee distributor system, defining time periods and scaling factors
//     // One week in seconds (7 days), used for epoch calculations
//     const WEEK: u64 = 7 * 86400;

//     // Deadline (1 day in seconds) for allowing token checkpoint updates
//     const TOKEN_CHECKPOINT_DEADLINE: u64 = 86400;

//     // Address of the developer or deployer, used as the initial admin and emergency return
//     const DEV: address = @dev;

//     // Seed for creating the fee distributor resource account
//     const FEE_DISTRIBUTOR_SEEDS: vector<u8> = b"FeeDistributor";

//     // Seed for creating the DXLYN token object account
//     const DXLYN_FA_SEED: vector<u8> = b"DXLYN";

//     // Scaling factor (10^12) for precision in calculations
//     const MULTIPLIER: u64 = 1000000000000;

//     // 1 QUANTS in smallest unit (10^8), for token amount scaling
//     const QUANTS: u64 = 100000000;

//     // Error codes for handling invalid operations and edge cases in the fee distributor system
//     /// Thrown when a non-admin attempts an admin-only action
//     const ERROR_NOT_ADMIN: u64 = 0x1;

//     /// Thrown when a non-authorized user attempts to checkpoint tokens
//     const ERROR_NOT_ALLOWED: u64 = 0x2;

//     /// Thrown when the contract is killed and operations are disabled
//     const ERROR_CONTRACT_KILLED: u64 = 0x3;

//     /// Thrown when the contract lacks sufficient DXLYN token balance
//     const ERROR_INSUFFICIENT_BALANCE: u64 = 0x4;

//     /// Thrown when a zero address is provided for admin or emergency return
//     const ERROR_ZERO_ADDRESS: u64 = 0x5;

//     /// Thrown when attempting to recover DXLYN tokens (not allowed)
//     const ERROR_CAN_NOT_RECOVER_DXLYN: u64 = 0x6;

//     //Events
//     #[event]
//     struct CommitAdmin has store, drop, copy {
//         admin: address
//     }

//     #[event]
//     struct ChangeEmergencyReturn has store, drop, copy {
//         new_emergency_return: address
//     }

//     #[event]
//     struct ApplyAdmin has store, drop, copy {
//         admin: address
//     }

//     #[event]
//     struct ToggleAllowCheckpointToken has store, drop, copy {
//         toggle_flag: bool
//     }

//     #[event]
//     struct CheckpointToken has drop, copy, store {
//         time: u64,
//         tokens: u64
//     }

//     #[event]
//     struct Claimed has store, drop, copy {
//         recipient: address,
//         amount: u64,
//         claim_epoch: u256,
//         max_epoch: u256,
//     }

//     #[event]
//     struct Point has drop, copy {
//         bias: u64,
//         slope: u64,
//         ts: u64,
//         blk: u64,
//     }


//     //Contact state
//     struct FeeDistributor has key {
//         start_time: u64,
//         time_cursor: u64,
//         // user time curser user -> time
//         time_cursor_of: Table<address, u64>,
//         // user epoch user -> epoch
//         user_epoch_of: Table<address, u256>,
//         last_token_time: u64,
//         // store time -> amount  note: change from array to table,
//         tokens_per_week: Table<u64, u64>,
//         coins: Object<FungibleStore>,
//         total_received: u64,
//         token_last_balance: u64,
//         // weekly veDxlyn supply time -> supply
//         ve_supply: Table<u64, u64>,
//         admin: address,
//         future_admin: address,
//         can_checkpoint_token: bool,
//         emergency_return: address,
//         is_killed: bool,
//         extended_ref: ExtendRef
//     }

//     fun init_module(sender: &signer) {
//         let constructor_ref = object::create_named_object(sender, FEE_DISTRIBUTOR_SEEDS);

//         let extended_ref = object::generate_extend_ref(&constructor_ref);

//         let object_signer = object::generate_signer(&constructor_ref);

//         let t: u64 = round_to_week(timestamp::now_seconds());

//         //dxlyn coin metadata
//         let dxlyn_coin_address = object::create_object_address(&DEV, DXLYN_FA_SEED);
//         let dxlyn_coin_metadata = object::address_to_object<Metadata>(dxlyn_coin_address);

//         move_to<FeeDistributor>(&object_signer, FeeDistributor {
//             start_time: t,
//             time_cursor: t,
//             last_token_time: t,
//             time_cursor_of: table::new<address, u64>(),
//             user_epoch_of: table::new<address, u256>(),
//             tokens_per_week: table::new<u64, u64>(),
//             coins: primary_fungible_store::create_primary_store(address_of(&object_signer), dxlyn_coin_metadata),
//             total_received: 0,
//             token_last_balance: 0,
//             ve_supply: table::new<u64, u64>(),
//             admin: DEV,
//             future_admin: @0x0,
//             can_checkpoint_token: false,
//             emergency_return: DEV,
//             is_killed: false,
//             extended_ref: extended_ref
//         });
//     }

//     #[view]
//     /// Get the address of the fee distributor
//     ///
//     /// # Returns
//     /// The address of the fee distributor resource.
//     public fun get_fee_distributor_address(): address {
//         object::create_object_address(&DEV, FEE_DISTRIBUTOR_SEEDS)
//     }


//     /// Checkpoint the token distribution
//     ///
//     /// # Arrguments
//     /// * `fee_dis`: A mutable reference to the `FeeDistributor` resource.
//     fun checkpoint_token_internal(fee_dis: &mut FeeDistributor) {
//         let token_balance = fungible_asset::balance(fee_dis.coins);
//         let to_distribute = token_balance - fee_dis.token_last_balance;
//         fee_dis.token_last_balance = token_balance;

//         let t = fee_dis.last_token_time;
//         let since_last = timestamp::now_seconds() - t;
//         fee_dis.last_token_time = timestamp::now_seconds();
//         let this_week = round_to_week(t);
//         let next_week = 0;

//         for (i in 0..20) {
//             // Calculate the start of the next week.
//             next_week = this_week + WEEK;

//             // Check if the current time is within the current week.
//             if (timestamp::now_seconds() < next_week) {
//                 // Handle edge case: no time has passed since the last checkpoint.
//                 if (since_last == 0 && timestamp::now_seconds() == t) {
//                     // All tokens go to the current week.
//                     let token_per_week = table::borrow_mut_with_default(&mut fee_dis.tokens_per_week, this_week, 0);
//                     *token_per_week = *token_per_week + to_distribute;
//                 }else {
//                     // Distribute tokens proportionally based on time spent in the current week.
//                     let token_per_week = table::borrow_mut_with_default(&mut fee_dis.tokens_per_week, this_week, 0);
//                     *token_per_week = *token_per_week + (to_distribute * (timestamp::now_seconds() - t) / since_last);
//                 };
//                 // Exit the loop as we've allocated tokens up to the current week.
//                 break
//             }else {
//                 if (since_last == 0 && next_week == t) {
//                     // All tokens go to the current week.
//                     let token_per_week = table::borrow_mut_with_default(&mut fee_dis.tokens_per_week, this_week, 0);
//                     *token_per_week = *token_per_week + to_distribute;
//                 }else {
//                     // Distribute tokens proportionally for the full week.
//                     let token_per_week = table::borrow_mut_with_default(&mut fee_dis.tokens_per_week, this_week, 0);
//                     *token_per_week = *token_per_week + (to_distribute * (next_week - t) / since_last);
//                 }
//             };
//             t = next_week;
//             this_week = next_week;
//         };

//         event::emit(CheckpointToken {
//             time: timestamp::now_seconds(),
//             tokens: to_distribute
//         })
//     }

//     /// Updates the token checkpoint.
//     ///
//     /// # Arguments
//     /// * `sender` - The signer calling the function.
//     ///
//     /// # Dev
//     /// Calculates the total number of tokens to be distributed in a given week.
//     /// During initial distribution, only the contract owner can call this.
//     /// After setup, it can be enabled for anyone to call.
//     public entry fun checkpoint_token(sender: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);
//         let sender_address = address_of(sender);
//         assert!(
//             sender_address == fee_dis.admin || (fee_dis.can_checkpoint_token && timestamp::now_seconds(
//             ) > fee_dis.last_token_time + TOKEN_CHECKPOINT_DEADLINE),
//             ERROR_NOT_ALLOWED
//         );
//         checkpoint_token_internal(fee_dis);
//     }

//     /// Find the epoch for a given timestamp.
//     ///
//     /// # Arguments
//     /// * `timestamp` - The timestamp to search for.
//     ///
//     /// # Returns
//     /// The epoch number corresponding to the given timestamp.
//     ///
//     /// # Dev
//     /// Uses binary search to find the epoch with the closest timestamp.
//     fun find_timestamp_epoch(timestamp: u64): u256 {
//         let min = 0;
//         let max = voting_escrow::epoch();

//         for (i in 0..128) {
//             if (min >= max) {
//                 break
//             };
//             let mid = (min + max + 2) / 2;
//             let (_, _, _, ts) = voting_escrow::point_history(mid);
//             if (ts <= timestamp) {
//                 min = mid;
//             }else {
//                 max = mid - 1;
//             }
//         };

//         min
//     }

//     /// Find the user epoch for a given user and timestamp.
//     ///
//     /// # Arguments
//     /// * `user` - The address of the user.
//     /// * `timestamp` - The timestamp to search for.
//     /// * `max_user_epoch` - The maximum user epoch.
//     ///
//     /// # Returns
//     /// The user epoch number corresponding to the given timestamp.
//     ///
//     /// # Dev
//     /// Uses binary search to find the user epoch with the closest timestamp.
//     fun find_timestamp_user_epoch(user: address, timestamp: u64, max_user_epoch: u256): u256 {
//         let min = 0;
//         let max = max_user_epoch;

//         for (i in 0..128) {
//             if (min >= max) {
//                 break
//             };
//             let mid = (min + max + 2) / 2;
//             let (_, _, _, ts) = voting_escrow::user_point_history(user, mid);
//             if (ts <= timestamp) {
//                 min = mid;
//             }else {
//                 max = mid - 1;
//             }
//         };

//         min
//     }

//     #[view]
//     /// Returns the veDXLYN balance for a user at a specific timestamp.
//     ///
//     /// # Arguments
//     /// * `user` - Address to query balance for.
//     /// * `timestamp` - Epoch time.
//     ///
//     /// # Returns
//     /// * `u64` - veDXLYN balance in 10^12 units.
//     public fun ve_for_at(user: address, timestamp: u64): u64 {
//         let max_user_epoch = voting_escrow::user_point_epoch(user);
//         let epoch = find_timestamp_user_epoch(user, timestamp, max_user_epoch);
//         let (bias, slope, _, ts) = voting_escrow::user_point_history(user, epoch);

//         let voting_power = bias - slope * (timestamp - ts);
//         max(voting_power, 0)
//     }


//     /// Updates the veDXLYN total supply checkpoint.
//     ///
//     /// # Dev
//     /// The checkpoint is also updated by the first claimant each new epoch week.
//     /// This function may be called independently of a claim to reduce claiming gas costs.
//     public entry fun checkpoint_total_supply() acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);
//         checkpoint_total_supply_internal(fee_dis);
//     }

//     /// Checkpoint the total supply of veDXLYN.
//     ///
//     /// # Arguments
//     /// * `fee_dis` - The FeeDistributor resource to update.
//     ///
//     /// # Dev
//     /// This function updates the veDXLYN supply for 20 weeks from the last checkpoint to the current time.
//     fun checkpoint_total_supply_internal(fee_dis: &mut FeeDistributor) {
//         let t = fee_dis.time_cursor;
//         let rounded_timestamp = round_to_week(timestamp::now_seconds());

//         voting_escrow::checkpoint();

//         for (i in 0..20) {
//             if (t > rounded_timestamp) {
//                 break
//             }else {
//                 let epoch = find_timestamp_epoch(t);
//                 let (bias, slope, _, ts) = voting_escrow::point_history(epoch);
//                 let dt = 0;
//                 if (t > ts) {
//                     //If the point is at 0 epoch, it can actually be earlier than the first deposit
//                     //Then make dt 0
//                     dt = t - ts;
//                 };
//                 table::upsert(&mut fee_dis.ve_supply, t, max((bias - slope * dt), 0));
//             };
//             t = t + WEEK
//         };

//         fee_dis.time_cursor = t;
//     }

//     /// Distributes tokens to a user based on their voting power up to `last_token_time`.
//     ///
//     /// # Arguments
//     /// * `fee_dis` - The FeeDistributor resource to update.
//     /// * `addr` - The user's address.
//     /// * `last_token_time` - The end timestamp for the claim period (week-aligned).
//     ///
//     /// # Returns
//     /// The amount of tokens to distribute.
//     fun claim_internal(fee_dis: &mut FeeDistributor, addr: address, last_token_time: u64): u64 {
//         // Initialize variables
//         let user_epoch: u256 = 0;
//         let to_distribute: u64 = 0;
//         let max_user_epoch = voting_escrow::user_point_epoch(addr);
//         let start_time = fee_dis.start_time;

//         // If user has no voting power, return 0
//         if (max_user_epoch == 0) {
//             return 0
//         };

//         // Get or initialize week cursor and user epoch
//         let week_cursor = *table::borrow_with_default(&fee_dis.time_cursor_of, addr, &0);
//         if (week_cursor == 0) {
//             // First claim, find the epoch at start_time
//             // Need to do the initial binary search
//             user_epoch = find_timestamp_user_epoch(addr, start_time, max_user_epoch);
//         } else {
//             user_epoch = *table::borrow_with_default(&fee_dis.user_epoch_of, addr, &0);
//         };

//         // Ensure user_epoch is at least 1
//         if (user_epoch == 0) {
//             user_epoch = 1;
//         };

//         // Get the user's voting point at user_epoch
//         let (bias, slope, blk, ts) = voting_escrow::user_point_history(addr, user_epoch);
//         let user_point = Point { slope: slope, bias: bias, ts: ts, blk: blk };

//         // Initialize week cursor if needed
//         if (week_cursor == 0) {
//             week_cursor = round_to_week(ts + WEEK - 1);
//         };

//         // Check if no tokens to claim
//         if (week_cursor >= last_token_time) {
//             return 0
//         };

//         // Ensure week_cursor is not before start_time
//         if (week_cursor < start_time) {
//             week_cursor = start_time;
//         };

//         // Initialize old point
//         let old_user_point = Point { slope: 0, bias: 0, ts: 0, blk: 0 };


//         // Iterate over weeks (up to 50 weeks)
//         for (i in 0..50) {
//             if (week_cursor >= last_token_time) {
//                 break
//             };

//             // Update epoch if week_cursor is past the current point's timestamp
//             if (week_cursor >= ts && user_epoch <= max_user_epoch) {
//                 user_epoch = user_epoch + 1;
//                 old_user_point = user_point;

//                 if (user_epoch > max_user_epoch) {
//                     // No more points, set to zero
//                     user_point = Point { slope: 0, bias: 0, ts: 0, blk: 0 };
//                 } else {
//                     // Get the next point
//                     let (ibias, islope, iblk, its) = voting_escrow::user_point_history(addr, user_epoch);
//                     user_point = Point { slope: islope, bias: ibias, ts: its, blk: iblk };
//                 };
//             } else {
//                 // Calculate voting power at week_cursor
//                 let dt = if (week_cursor > old_user_point.ts) { week_cursor - old_user_point.ts } else { 0 };
//                 let balance_of = max(old_user_point.bias - dt * old_user_point.slope, 0);

//                 // Break if no balance and no more epochs
//                 if (balance_of == 0 && user_epoch > max_user_epoch) {
//                     break
//                 };

//                 // Calculate tokens to distribute
//                 if (balance_of > 0) {
//                     let tokens_per_week = *table::borrow_with_default(&fee_dis.tokens_per_week, week_cursor, &0);
//                     let ve_supply = *table::borrow_with_default(&fee_dis.ve_supply, week_cursor, &0);

//                     // converted into u256 for handle overflow issue
//                     let to_distribute_internal: u256 = (balance_of as u256) * (tokens_per_week as u256) / (ve_supply as u256);
//                     // to_distribute = to_distribute + (balance_of * tokens_per_week / ve_supply);
//                     to_distribute = to_distribute + (to_distribute_internal as u64);
//                 };

//                 week_cursor = week_cursor + WEEK;
//             };
//         };

//         // Update user state
//         user_epoch = if (max_user_epoch < user_epoch - 1) { max_user_epoch } else { user_epoch - 1 };
//         table::upsert(&mut fee_dis.user_epoch_of, addr, user_epoch);
//         table::upsert(&mut fee_dis.time_cursor_of, addr, week_cursor);


//         // Emit Claimed event
//         event::emit(Claimed {
//             recipient: addr,
//             amount: to_distribute,
//             claim_epoch: user_epoch,
//             max_epoch: max_user_epoch,
//         });

//         to_distribute
//     }


//     /// Claims fees for the sender.
//     ///
//     /// # Arguments
//     /// * `sender` - The signer requesting the claim.
//     ///
//     /// # Dev
//     /// Each call to `claim` processes up to 50 weeks of veDXLYN points.
//     /// For accounts with extensive veDXLYN activity, multiple calls may be needed to claim all available fees.
//     /// The `Claimed` event indicates if more claims are possible: if `claim_epoch` < `max_epoch`, the account can claim again.
//     public entry fun claim(sender: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(!fee_dis.is_killed, ERROR_CONTRACT_KILLED);

//         // Update total voting supply if time_cursor is reached
//         if (timestamp::now_seconds() >= fee_dis.time_cursor) {
//             checkpoint_total_supply_internal(fee_dis);
//         };

//         // Perform token checkpoint if allowed and deadline passed
//         let last_token_time = fee_dis.last_token_time;

//         if (fee_dis.can_checkpoint_token && timestamp::now_seconds() > last_token_time + TOKEN_CHECKPOINT_DEADLINE) {
//             checkpoint_token_internal(fee_dis);
//             last_token_time = timestamp::now_seconds();
//         };

//         // Round last_token_time to the start of the week
//         last_token_time = round_to_week(last_token_time);

//         // Call claim_internal to calculate and distribute tokens
//         let amount = claim_internal(fee_dis, address_of(sender), last_token_time);

//         // Update token_last_balance
//         if (amount > 0) {
//             let fee_dis_signer = object::generate_signer_for_extending(&fee_dis.extended_ref);
//             let dxlyn_metadata = fungible_asset::store_metadata(fee_dis.coins);
//             let to_wallet = primary_fungible_store::ensure_primary_store_exists(address_of(sender), dxlyn_metadata);

//             fungible_asset::transfer(&fee_dis_signer, fee_dis.coins, to_wallet, amount);

//             fee_dis.token_last_balance = fee_dis.token_last_balance - amount;
//         };
//     }


//     /// Make multiple fee claims in a single call.
//     ///
//     /// # Parameters
//     /// - `receivers`: List of addresses to claim for. Claiming terminates at the first `ZERO_ADDRESS`.
//     ///
//     /// # Dev
//     /// Used to claim for many accounts at once, or to make multiple claims for the same address when that address has significant veDXLYN history.
//     public entry fun claim_many(_sender: &signer, receivers: vector<address>) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);
//         assert!(!fee_dis.is_killed, ERROR_CONTRACT_KILLED);

//         // Update total voting supply if time_cursor is reached
//         if (timestamp::now_seconds() >= fee_dis.time_cursor) {
//             checkpoint_total_supply_internal(fee_dis);
//         };

//         let last_token_time = fee_dis.last_token_time;

//         if (fee_dis.can_checkpoint_token && timestamp::now_seconds(
//         ) > fee_dis.last_token_time + TOKEN_CHECKPOINT_DEADLINE) {
//             checkpoint_token_internal(fee_dis);
//             last_token_time = timestamp::now_seconds();
//         };

//         // Round last_token_time to the start of the week
//         let last_token_time = round_to_week(last_token_time);

//         // Claim for each address
//         let total: u64 = 0;
//         let len = vector::length(&receivers);


//         for (i in 0..len) {
//             let addr = *vector::borrow(&receivers, i);
//             if (addr == @0x0) {
//                 break
//             };

//             let amount = claim_internal(fee_dis, addr, last_token_time);
//             if (amount > 0) {
//                 let fee_dis_signer = object::generate_signer_for_extending(&fee_dis.extended_ref);
//                 let dxlyn_metadata = fungible_asset::store_metadata(fee_dis.coins);
//                 let to_wallet = primary_fungible_store::ensure_primary_store_exists(addr, dxlyn_metadata);

//                 fungible_asset::transfer(&fee_dis_signer, fee_dis.coins, to_wallet, amount);

//                 total = total + amount;
//             };
//         };

//         // Update token_last_balance
//         if (total > 0) {
//             let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);
//             assert!(fee_dis.token_last_balance >= total, ERROR_INSUFFICIENT_BALANCE);
//             fee_dis.token_last_balance = fee_dis.token_last_balance - total;
//         };
//     }

//     /// Receive DXLYN into the contract and trigger a token checkpoint.
//     ///
//     /// # Arguments
//     /// * `sender` - The signer sending the DXLYN.
//     /// * `amount` - The amount of DXLYN to send.
//     public entry fun burn(sender: &signer, amount: u64) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);
//         assert!(!fee_dis.is_killed, ERROR_CONTRACT_KILLED);

//         if (amount > 0) {
//             let dxlyn_metadata = fungible_asset::store_metadata(fee_dis.coins);

//             let coin_to_distribute = primary_fungible_store::withdraw(sender, dxlyn_metadata, amount);

//             fungible_asset::deposit(fee_dis.coins, coin_to_distribute);

//             if (fee_dis.can_checkpoint_token && timestamp::now_seconds(
//             ) > fee_dis.last_token_time + TOKEN_CHECKPOINT_DEADLINE) {
//                 checkpoint_token_internal(fee_dis)
//             };
//         }
//     }


//     /// Commit transfer of ownership.
//     ///
//     /// # Arguments
//     /// * `admin` - The current admin signer.
//     /// * `new_future_admin` - The new admin address.
//     public entry fun commit_admin(admin: &signer, new_future_admin: address) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         fee_dis.future_admin = new_future_admin;

//         event::emit(CommitAdmin {
//             admin: new_future_admin
//         })
//     }

//     /// Apply transfer of ownership.
//     ///
//     /// # Arguments
//     /// * `admin` - The current admin signer.
//     public entry fun apply_admin(admin: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);
//         assert!(fee_dis.future_admin != @0x0, ERROR_ZERO_ADDRESS);

//         fee_dis.admin = fee_dis.future_admin;

//         event::emit(ApplyAdmin {
//             admin: fee_dis.future_admin
//         })
//     }

//     /// Toggle permission for checkpointing by any account.
//     ///
//     /// # Arguments
//     /// * `admin` - The admin signer.
//     public entry fun toggle_allow_checkpoint_token(admin: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         let flag = !fee_dis.can_checkpoint_token;

//         fee_dis.can_checkpoint_token = flag;

//         event::emit(ToggleAllowCheckpointToken {
//             toggle_flag: flag
//         })
//     }

//     /// Kill the contract.
//     ///
//     /// Killing transfers the entire DXLYN balance to the emergency return address
//     /// and blocks the ability to claim or burn. The contract cannot be unkilled.
//     public entry fun kill_me(admin: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         fee_dis.is_killed = true;

//         let fee_dis_signer = object::generate_signer_for_extending(&fee_dis.extended_ref);
//         let dxlyn_metadata = fungible_asset::store_metadata(fee_dis.coins);
//         let to_wallet = primary_fungible_store::ensure_primary_store_exists(fee_dis.emergency_return, dxlyn_metadata);

//         let total_amount = fungible_asset::balance(fee_dis.coins);

//         fungible_asset::transfer(&fee_dis_signer, fee_dis.coins, to_wallet, total_amount);
//     }


//     /// Recover any OLD (Legacy Token) tokens from this contract.
//     ///
//     /// # Type Parameters
//     /// - `CoinType`: The legacy coin type to recover.
//     ///
//     /// # Parameters
//     /// - `admin`: The admin signer.
//     ///
//     /// # Dev
//     /// Tokens are sent to the emergency return address.
//     public entry fun recover_balance_legacy_coin<CoinType>(admin: &signer) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         let fee_dis_signer = object::generate_signer_for_extending(&fee_dis.extended_ref);

//         let amount = coin::balance<CoinType>(address_of(&fee_dis_signer));

//         supra_account::transfer_coins<CoinType>(&fee_dis_signer, fee_dis.emergency_return, amount);
//     }


//     /// Recover any FA tokens from this contract except DXLYN.
//     /// Tokens are sent to the emergency return address.
//     ///
//     /// # Arguments
//     /// * `admin` - The admin signer.
//     /// * `coin` - The token address to recover.
//     public entry fun recover_balance_fa(admin: &signer, coin: address) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         let dxlyn_metadata = fungible_asset::store_metadata(fee_dis.coins);
//         let dxlyn_address = object::object_address(&dxlyn_metadata);

//         assert!(dxlyn_address != coin, ERROR_CAN_NOT_RECOVER_DXLYN);

//         let fee_dis_signer = object::generate_signer_for_extending(&fee_dis.extended_ref);

//         let coin_metadata = object::address_to_object<Metadata>(coin);

//         let amount = primary_fungible_store::balance(address_of(&fee_dis_signer), coin_metadata);

//         primary_fungible_store::transfer(&fee_dis_signer, coin_metadata, fee_dis.emergency_return, amount);
//     }


//     /// Changes the emergency return address.
//     ///
//     /// # Arguments
//     /// * `admin` - The admin signer.
//     /// * `new_emergency_return` - New emergency return address.
//     public entry fun change_emergency_return(admin: &signer, new_emergency_return: address) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global_mut<FeeDistributor>(fee_dis_address);

//         assert!(address_of(admin) == fee_dis.admin, ERROR_NOT_ADMIN);

//         assert!(new_emergency_return != @0x0, ERROR_ZERO_ADDRESS);

//         fee_dis.emergency_return = new_emergency_return;

//         event::emit(ChangeEmergencyReturn {
//             new_emergency_return: new_emergency_return
//         })
//     }

//     /// Round a timestamp to the start of the week
//     ///
//     /// # Arguments
//     /// * `timestamp` - The timestamp to round.
//     fun round_to_week(timestamp: u64): u64 {
//         timestamp / WEEK * WEEK
//     }


//     #[test_only]
//     public fun initialize(res: &signer) {
//         init_module(res);
//     }

//     #[test_only]
//     public fun get_fee_distributor_state(): (
//         u64, // start_time
//         u64, // time_cursor
//         u64, // last_token_time
//         u64, // coins balance
//         u64, // total_received
//         u64, // token_last_balance
//         address, // admin
//         address, // future_admin
//         bool, // can_checkpoint_token
//         address, // emergency_return
//         bool, // is_killed
//     ) acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global<FeeDistributor>(fee_dis_address);
//         (
//             fee_dis.start_time,
//             fee_dis.time_cursor,
//             fee_dis.last_token_time,
//             fungible_asset::balance(fee_dis.coins),
//             fee_dis.total_received,
//             fee_dis.token_last_balance,
//             fee_dis.admin,
//             fee_dis.future_admin,
//             fee_dis.can_checkpoint_token,
//             fee_dis.emergency_return,
//             fee_dis.is_killed,
//         )
//     }

//     #[test_only]
//     public fun get_tokens_per_week(_timestamp: u64): u64 acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global<FeeDistributor>(fee_dis_address);

//         *table::borrow_with_default(&fee_dis.tokens_per_week, round_to_week(_timestamp), &0)
//     }

//     #[test_only]
//     public fun get_ve_supply_at(_timestamp: u64): u64 acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global<FeeDistributor>(fee_dis_address);

//         *table::borrow_with_default(&fee_dis.ve_supply, round_to_week(_timestamp), &0)
//     }

//     #[test_only]
//     public fun get_user_epoch(add: address): u256 acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global<FeeDistributor>(fee_dis_address);

//         *table::borrow_with_default(&fee_dis.user_epoch_of, add, &0)
//     }

//     #[test_only]
//     public fun get_user_time_cursor_of(add: address): u64 acquires FeeDistributor {
//         let fee_dis_address = get_fee_distributor_address();
//         let fee_dis = borrow_global<FeeDistributor>(fee_dis_address);

//         *table::borrow_with_default(&fee_dis.time_cursor_of, add, &0)
//     }
// }