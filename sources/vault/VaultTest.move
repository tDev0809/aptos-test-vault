#[test_only]
module TestVault::EscrowTests {
    use std::string;
    use std::signer;
    use std::unit_test;
    use std::vector;
    use aptos_framework::coin as Coin;

    use TestVault::Escrow;
    
    struct CoinCapabilities has key {
        mint_cap: Coin::MintCapability<Escrow::ManagedCoin>,
        burn_cap: Coin::BurnCapability<Escrow::ManagedCoin>,
    }

    fun get_account(): signer {
        vector::pop_back(&mut unit_test::create_signers_for_testing(1))
    }

    #[test(coin_owner = @TestVault)]
    public entry fun init_deposit_withdraw_escrow(coin_owner: signer) {
        let admin = get_account();
        let addr = signer::address_of(&admin);

        let name = string::utf8(b"Fake money");
        let symbol = string::utf8(b"FMD");

        let (mint_cap, burn_cap) = Coin::initialize<Escrow::ManagedCoin>(
            &coin_owner,
            name,
            symbol,
            18,
            true
        );
        Coin::register<Escrow::ManagedCoin>(&coin_owner);
        let coins_minted = Coin::mint<Escrow::ManagedCoin>(100000, &mint_cap);
        Coin::deposit(signer::address_of(&coin_owner), coins_minted);
        move_to(&coin_owner, CoinCapabilities {
            mint_cap,
            burn_cap
        });

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

        if (!Coin::is_account_registered<Escrow::ManagedCoin>(user_addr)) {
            Coin::register<Escrow::ManagedCoin>(&user);
        };


        Coin::transfer<Escrow::ManagedCoin>(&coin_owner, user_addr, 10);

        Escrow::deposit(&user, 10, addr);
        assert!(
          Escrow::get_user_info(user_addr) == 10,
          1
        );

        Escrow::withdraw(&user, 10, addr);
        assert!(
          Escrow::get_user_info(user_addr) == 0,
          1
        );
    }
}
