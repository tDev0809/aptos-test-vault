#[test_only]
module TestVault::EscrowTests {
    use std::signer;
    use std::unit_test;
    use std::vector;
    use aptos_framework::coin as Coin;

    use TestVault::Escrow;

    fun get_account(): signer {
        vector::pop_back(&mut unit_test::create_signers_for_testing(1))
    }

    #[test]
    public entry fun init_deposit_withdraw_escrow() {
        let admin = get_account();
        let addr = signer::address_of(&admin);
        if (!Escrow::is_initialized_valut(addr)) {
            Escrow::init_escrow(&admin);
        };

        assert!(
          Escrow::get_vault_status(addr) == false,
          0
        );
        
        Escrow::pause_escrow(&admin);
        assert!(
          Escrow::get_vault_status(addr) == true,
          0
        );
        
        Escrow::resume_escrow(&admin);
        assert!(
          Escrow::get_vault_status(addr) == false,
          0
        );
        
        let user = get_account();
        let user_addr = signer::address_of(&user);

        let to_mint = Coin::withdraw<Escrow::ManagedCoin>(&user, 1000);
        let coins_minted = Coin::mint<Escrow::ManagedCoin>(1000, &to_mint.mint_cap);
        Coin::deposit(user_addr, coins_minted);

        Escrow::deposit(&user, 10, addr);
        assert!(
          Escrow::get_user_info(user_addr) == 10,
          1
        );
    }
}
