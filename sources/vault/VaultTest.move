#[test_only]
module test_vault::test_vault {
    use std::signer;
    use aptos_framework::coin;
    use test_vault::token;
    use test_vault::vault;
    
    #[test(token_owner = @0xAB, coin_owner = @0x1, aptos_framework = @aptos_framework)]
    public entry fun test_escrow_coin_for_token(token_owner: signer, coin_owner: signer, aptos_framework: signer) acquires vault::TokenStoreEscrow, vault::TokenListings {
        let token_id = token::create_collection_and_token(&token_owner, 100, 100, 100);
        token::initialize_token_store(&coin_owner);
        coin::create_fake_money(&coin_owner, &token_owner, 100);

        vault::list_token_for_vault<coin::FakeMoney>(&token_owner, token_id, 100);
        // coin owner only has 50 coins left
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(&coin_owner)) == 50, 1);
        // all tokens in token escrow or transferred. Token owner has 0 token in token_store
        assert!(token::balance_of(signer::address_of(&token_owner), token_id) == 0, 1);

        let token_listing = &borrow_global<vault::TokenListings<coin::FakeMoney>>(signer::address_of(&token_owner)).listings;

        // completely sold, no listing left
        assert!(table::length(token_listing) == 1, 1);
        let token_coin_vault = table::borrow(token_listing, token_id);
        // sold 50 token only 50 tokens left
        assert!(token_coin_vault.token_amount == 50, token_coin_vault.token_amount);
    }
}