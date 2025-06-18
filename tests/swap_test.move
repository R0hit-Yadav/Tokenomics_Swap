module dxlyn::dxlyn_swap_test {
    use std::signer;
    use std::vector;
    use std::string::{utf8};
    use std::debug::print;
    use supra_framework::coin;
    use supra_framework::primary_fungible_store;
    use supra_framework::object;
    use supra_framework::fungible_asset::Metadata;
    use supra_framework::account;
    use dxlyn::dxlyn_swap;
    use dxlyn::dxlyn_coin;
    use dxlyn::wdxlyn_coin;

    const DEV: address = @dev;

    #[test_only]
    fun setup_test(admin: &signer) {
        dxlyn_coin::init_coin(admin);
        dxlyn_swap::init_module_test_swap(admin);
    }

    #[test_only]
    fun create_and_mint(admin: &signer, user: &signer, amount: u64) {
        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        dxlyn_coin::register_and_mint(admin, user_addr, amount);
    }

    #[test(admin = @dev, user = @0x123)]
    fun test_swap_fa_to_dxlyn_and_back(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        let user_addr = signer::address_of(user);

        // Swap 40 FA to DXLYN
        dxlyn_swap::swap_fa_to_dxlyn(user, 40);

        // Check locked FA and DXLYN balance
        let locked = dxlyn_swap::get_locked_fa(user_addr);
        let dxlyn_balance = coin::balance<wdxlyn_coin::DXLYN>(user_addr);
        assert!(locked == 40, 100);
        assert!(dxlyn_balance == 40, 101);

        // Swap 20 DXLYN back to FA
        dxlyn_swap::swap_dxlyn_to_fa(user, 20);

        let locked2 = dxlyn_swap::get_locked_fa(user_addr);
        let dxlyn_balance2 = coin::balance<wdxlyn_coin::DXLYN>(user_addr);
        assert!(locked2 == 20, 102);
        assert!(dxlyn_balance2 == 20, 103);

        // Check user FA balance
        let fa_metadata_addr = object::create_object_address(&DEV, b"DXLYN");
        let fa_metadata = object::address_to_object<Metadata>(fa_metadata_addr);
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        assert!(fa_balance == 80, 104);
    }

    #[test(admin = @dev, user1 = @0x123, user2 = @0x456)]
    fun test_swap_fa_to_dxlyn_multiple_users(admin: &signer, user1: &signer, user2: &signer) {
        setup_test(admin);
        create_and_mint(admin, user1, 50);
        create_and_mint(admin, user2, 70);

        let user_addr1 = signer::address_of(user1);
        let user_addr2 = signer::address_of(user2);

        dxlyn_swap::swap_fa_to_dxlyn(user1, 30);
        dxlyn_swap::swap_fa_to_dxlyn(user2, 50);

        let locked1 = dxlyn_swap::get_locked_fa(user_addr1);
        let locked2 = dxlyn_swap::get_locked_fa(user_addr2);
        assert!(locked1 == 30, 200);
        assert!(locked2 == 50, 201);

        let dxlyn1 = coin::balance<wdxlyn_coin::DXLYN>(user_addr1);
        let dxlyn2 = coin::balance<wdxlyn_coin::DXLYN>(user_addr2);
        assert!(dxlyn1 == 30, 202);
        assert!(dxlyn2 == 50, 203);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_fa_to_dxlyn_insufficient_balance(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        // Try to swap more than balance
        dxlyn_swap::swap_fa_to_dxlyn(user, 200);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_dxlyn_to_fa_no_locked(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        // Try to swap back without having swapped first
        dxlyn_swap::swap_dxlyn_to_fa(user, 100);
    }

    #[test(admin = @dev, user = @0x123)]
    fun test_swap_full_cycle(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 1000);

        let user_addr = signer::address_of(user);

        // Swap all FA to DXLYN
        dxlyn_swap::swap_fa_to_dxlyn(user, 1000);

        assert!(dxlyn_coin::get_user_dxlyn_balance(user_addr) == 0, 0);
        assert!(dxlyn_swap::get_locked_fa(user_addr) == 1000, 1);
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) == 1000, 2);

        // Swap all DXLYN back to FA
        dxlyn_swap::swap_dxlyn_to_fa(user, 1000);

        assert!(dxlyn_coin::get_user_dxlyn_balance(user_addr) == 1000, 3);
        assert!(dxlyn_swap::get_locked_fa(user_addr) == 0, 4);
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) == 0, 5);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_dxlyn_to_fa_insufficient_dxlyn(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        // Swap some FA to DXLYN
        dxlyn_swap::swap_fa_to_dxlyn(user, 50);

        // Try to swap more DXLYN than owned
        dxlyn_swap::swap_dxlyn_to_fa(user, 100);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_fa_to_dxlyn_zero_amount(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        // Try to swap zero FA
        dxlyn_swap::swap_fa_to_dxlyn(user, 0);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_dxlyn_to_fa_zero_amount(admin: &signer, user: &signer) {
        setup_test(admin);
        create_and_mint(admin, user, 100);

        dxlyn_swap::swap_fa_to_dxlyn(user, 50);

        // Try to swap zero DXLYN
        dxlyn_swap::swap_dxlyn_to_fa(user, 0);
    }
}