module dxlyn::dxlyn_swap_test {
    use std::signer;
    use supra_framework::coin;
    use supra_framework::primary_fungible_store;
    use supra_framework::object;
    use supra_framework::fungible_asset::Metadata;
    use dxlyn::dxlyn_swap;
    use supra_framework::account;
    use dxlyn::dxlyn_coin;
    use dxlyn::wdxlyn_coin;
    use std::debug::print;
    use std::string::{utf8};

    const DEV: address = @dev;

    // Test Cases 
    #[test(admin=@dev, user=@0x123)]
    public fun test_swap_fa_to_dxlyn_and_back(admin: &signer, user: &signer) {
  
        dxlyn_coin::init_coin(admin); // FA
        dxlyn_swap::init_module_test_swap(admin);// wDxlyn

        account::create_account_for_test(@0x1);
        let supra_framework_sign = account::create_signer_for_test(@0x1);
        coin::create_coin_conversion_map(&supra_framework_sign);

        let user_addr = signer::address_of(user);
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);

        // mint 100 FA to user
        dxlyn_coin::register_and_mint(admin, signer::address_of(user), 100);
        print(&utf8(b"register and mint 100 FA to user"));

        let fa_metadata_addr = object::create_object_address(&DEV, b"DXLYN");
        let fa_metadata = object::address_to_object<Metadata>(fa_metadata_addr);
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        print(&fa_balance);

        // Swap 40 FA to DXLYN
        print(&utf8(b"Swap 40 FA to DXLYN"));
        dxlyn_swap::swap_fa_to_dxlyn(user, 40);
        print(&utf8(b"After Swap"));
        print(&utf8(b"Locked FA:"));
        print(&dxlyn_swap::get_locked_fa(user_addr));
        print(&utf8(b"DXLYN balance:"));
        print(&coin::balance<wdxlyn_coin::DXLYN>(user_addr));


        // check lock fa balance
        let user_addr = signer::address_of(user);
        let locked = dxlyn_swap::get_locked_fa(user_addr);
        assert!(locked == 40, 100);

        // check user DXLYN coin balance
        let dxlyn_balance = coin::balance<wdxlyn_coin::DXLYN>(user_addr);
        assert!(dxlyn_balance == 40, 101);

        // swap 20 DXLYN back to FA
        print(&utf8(b"Swap 20 DXLYN back to FA"));
        dxlyn_swap::swap_dxlyn_to_fa(user, 20);
        print(&utf8(b"After Swap back"));
        print(&utf8(b"Locked FA:"));
        print(&dxlyn_swap::get_locked_fa(user_addr));
        print(&utf8(b"DXLYN balance:"));
        print(&coin::balance<wdxlyn_coin::DXLYN>(user_addr));

        //now check new locked FA balance
        let locked2 = dxlyn_swap::get_locked_fa(user_addr);
        assert!(locked2 == 20, 102);

        //now check new user DXLYN coin balance
        let dxlyn_balance2 = coin::balance<wdxlyn_coin::DXLYN>(user_addr);
        assert!(dxlyn_balance2 == 20, 103);

        //check user primary fungible store balance
        let fa_metadata_addr = object::create_object_address(&DEV, b"DXLYN");
        let fa_metadata = object::address_to_object<Metadata>(fa_metadata_addr);
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        assert!(fa_balance == 80, 104);
    }

    #[test(admin=@dev, user1=@0x123, user2=@0x456)]
    public fun test_swap_fa_to_dxlyn_multiple_users(admin: &signer, user1: &signer, user2: &signer) {
        print(&utf8(b"Test swap FA to DXLYN for multiple users"));
        dxlyn_coin::init_coin(admin);
        dxlyn_swap::init_module_test_swap(admin);

        let user_addr1 = signer::address_of(user1);
        let user_addr2 = signer::address_of(user2);
        let admin_addr = signer::address_of(admin);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr1);
        account::create_account_for_test(user_addr2);


        print(&utf8(b"register and mint 50 FA to user1"));
        print(&utf8(b"register and mint 70 FA to user2"));
        dxlyn_coin::register_and_mint(admin, signer::address_of(user1), 50);
        dxlyn_coin::register_and_mint(admin, signer::address_of(user2), 70);


        let fa_metadata_addr = object::create_object_address(&DEV, b"DXLYN");
        let fa_metadata = object::address_to_object<Metadata>(fa_metadata_addr);
        let fa_balance1 = primary_fungible_store::balance(user_addr1, fa_metadata);
        let fa_balance2 = primary_fungible_store::balance(user_addr2, fa_metadata);

        print(&fa_balance1);
        print(&fa_balance2);

        print(&utf8(b"Swap 30 FA to DXLYN for user1"));
        print(&utf8(b"Swap 50 FA to DXLYN for user2"));

        dxlyn_swap::swap_fa_to_dxlyn(user1, 30);
        dxlyn_swap::swap_fa_to_dxlyn(user2, 50);
        
        print(&utf8(b"after swap locked FA and DXLYN balance"));
        print(&dxlyn_swap::get_locked_fa(signer::address_of(user1)));
        print(&dxlyn_swap::get_locked_fa(signer::address_of(user2)));
        print(&coin::balance<wdxlyn_coin::DXLYN>(signer::address_of(user1)));
        print(&coin::balance<wdxlyn_coin::DXLYN>(signer::address_of(user2)));

        let locked1 = dxlyn_swap::get_locked_fa(signer::address_of(user1));
        let locked2 = dxlyn_swap::get_locked_fa(signer::address_of(user2));
        assert!(locked1 == 30, 200);
        assert!(locked2 == 50, 201);

        let dxlyn1 = coin::balance<wdxlyn_coin::DXLYN>(signer::address_of(user1));
        let dxlyn2 = coin::balance<wdxlyn_coin::DXLYN>(signer::address_of(user2));
        assert!(dxlyn1 == 30, 202);
        assert!(dxlyn2 == 50, 203);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_fa_to_dxlyn_insufficient_balance(admin: &signer, user: &signer) {
        print(&utf8(b"Test swap FA to DXLYN with insufficient balance"));
        dxlyn_coin::init_coin(admin);
        dxlyn_swap::init_module_test_swap(admin);

        let user_addr = signer::address_of(user);
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        
        // Mint small amount
        print(&utf8(b"Mint 100 FA to user"));
        dxlyn_coin::register_and_mint(admin,user_addr, 100);

        print(&utf8(b"Balance before swap:"));
        let fa_metadata = object::address_to_object<Metadata>(object::create_object_address(&DEV, b"DXLYN"));
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        print(&fa_balance);

        print(&utf8(b"Try to swap 200 FA to DXLYN"));
        // Try to swap more than balance
        dxlyn_swap::swap_fa_to_dxlyn(user, 200);
    }

    #[test(admin = @dev, user = @0x123)]
    #[expected_failure]
    fun test_swap_dxlyn_to_fa_no_locked(admin: &signer, user: &signer) {
        print(&utf8(b"Test swap DXLYN to FA without locked FA"));
        dxlyn_coin::init_coin(admin);
        dxlyn_swap::init_module_test_swap(admin);

        let user_addr = signer::address_of(user);
        let admin_addr = signer::address_of(admin);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        
        print(&utf8(b"swap 100 DXLYN to FA without locked FA"));
        let fa_metadata = object::address_to_object<Metadata>(object::create_object_address(&DEV, b"DXLYN"));
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        print(&fa_balance);
        // Try to swap back without having swapped first
        dxlyn_swap::swap_dxlyn_to_fa(user, 100);
    }

    #[test(admin = @dev, user = @0x123)]
    fun test_swap_full_cycle(admin: &signer, user: &signer) {
        print(&utf8(b"Test full swap cycle: FA to DXLYN and back"));
        dxlyn_coin::init_coin(admin);
        dxlyn_swap::init_module_test_swap(admin);

        let user_addr = signer::address_of(user);
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);
        
        print(&utf8(b"Mint 1000 FA to user"));
        // Mint FA to user
        dxlyn_coin::register_and_mint(admin, user_addr, 1000);

        let fa_metadata = object::address_to_object<Metadata>(object::create_object_address(&DEV, b"DXLYN"));
        let fa_balance = primary_fungible_store::balance(user_addr, fa_metadata);
        print(&fa_balance);
        
        print(&utf8(b"Swap 1000 FA to DXLYN"));
        // Swap FA to DXLYN
        dxlyn_swap::swap_fa_to_dxlyn(user, 1000);
        
        // Verify all FA is locked
        print(&utf8(b"After Swap"));
        print(&utf8(b"Locked FA:"));
        print(&dxlyn_swap::get_locked_fa(user_addr));
        print(&utf8(b"DXLYN balance:"));
        print(&coin::balance<wdxlyn_coin::DXLYN>(user_addr));

        assert!(dxlyn_coin::get_user_dxlyn_balance(user_addr) == 0, 0);
        assert!(dxlyn_swap::get_locked_fa(user_addr) == 1000, 1);
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) == 1000, 2);
        
        // Swap back DXLYN to FA
        print(&utf8(b"Swap back 1000 DXLYN to FA"));
        dxlyn_swap::swap_dxlyn_to_fa(user, 1000);
        
        print(&utf8(b"After Swap back"));
        print(&utf8(b"Locked FA:"));
        print(&dxlyn_swap::get_locked_fa(user_addr));
        print(&utf8(b"DXLYN balance:"));
        print(&coin::balance<wdxlyn_coin::DXLYN>(user_addr));
        // Verify all is returned
        assert!(dxlyn_coin::get_user_dxlyn_balance(user_addr) == 1000, 3);
        assert!(dxlyn_swap::get_locked_fa(user_addr) == 0, 4);
        assert!(coin::balance<wdxlyn_coin::DXLYN>(user_addr) == 0, 5);
    }
}