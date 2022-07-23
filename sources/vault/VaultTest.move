#[test_only]
module TestVault::EscrowTests {
    use std::signer;
    use std::unit_test;
    use std::vector;
    use std::string;

    use TestVault::Escrow;

    fun get_account(): signer {
        vector::pop_back(&mut unit_test::create_signers_for_testing(1))
    }

    #[test]
    public entry fun init_deposit_withdraw_escrow() {
        let admin = get_account();
        let addr = signer::address_of(&admin);
        Escrow::init_escrow(admin);

        let user = get_account();
        
        assert!(
          Message::get_message(addr) == string::utf8(b"Hello, Blockchain"),
          0
        );
    }
}
