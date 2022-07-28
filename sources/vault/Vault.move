/// A module for
/// 1. Hold tokens escrow to prevent token been transferred
/// 2. List token for vault with a targeted CoinType.
module test_vault::vault {
    use aptos_std::event::{Self, EventHandle};
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_token::token_v1::{Self, Token, TokenId, deposit_token, withdraw_token, merge, split};

    const ETOKEN_ALREADY_LISTED: u64 = 1;
    const ETOKEN_LISTING_NOT_EXIST: u64 = 2;
    const ETOKEN_NOT_IN_ESCROW: u64 = 3;
    const ETOKEN_MIN_PRICE_NOT_MATCH: u64 = 4;
    const ETOKEN_AMOUNT_NOT_MATCH: u64 = 5;
    const ENOT_ENOUGH_COIN: u64 = 6;

    /// TokenCoinVault records a vault ask for escrowing token_amount with CoinType
    struct TokenCoinVault<phantom CoinType> has store, drop {
        token_amount: u64,
    }

    /// The listing of all tokens for vault stored at token owner's account
    struct TokenListings<phantom CoinType> has key {
        // key is the token id for vault.
        listings: Table<TokenId, TokenCoinVault<CoinType>>,
        listing_events: EventHandle<TokenListingEvent>,
        vault_events: EventHandle<TokenVaultEvent>,
    }

    /// TokenEscrow holds the tokens that cannot be withdrawn or transferred
    struct TokenEscrow has store {
        token: Token,
    }

    /// TokenStoreEscrow holds a map of token id to their tokenEscrow
    struct TokenStoreEscrow has key {
        token_escrows: Table<TokenId, TokenEscrow>,
    }

    struct TokenListingEvent has drop, store {
        token_id: TokenId,
        amount: u64,
        min_price: u64,
        coin_type_info: TypeInfo,
    }

    struct TokenVaultEvent has drop, store {
        token_id: TokenId,
        token_buyer: address,
        token_amount: u64,
        coin_amount: u64,
        coin_type_info: TypeInfo,
    }

    /// Token owner lists their token for vault
    public entry fun list_token_for_vault<CoinType>(
        token_owner: &signer,
        token_id: TokenId,
        token_amount: u64,
    ) acquires TokenStoreEscrow, TokenListings {
        initialize_token_store_escrow(token_owner);
        // withdraw the token and store them to the token_owner's TokenEscrow
        let token = withdraw_token(token_owner, token_id, token_amount);
        deposit_token_to_escrow(token_owner, token_id, token);
        // add the exchange info TokenCoinVault list
        initialize_token_listing<CoinType>(token_owner);
        let token_coin_vault = TokenCoinVault<CoinType>{
            token_amount,
        };
        let listing = &mut borrow_global_mut<TokenListings<CoinType>>(signer::address_of(token_owner)).listings;
        assert!(!table::contains(listing, token_id), ETOKEN_ALREADY_LISTED);
        table::add(listing, token_id, token_coin_vault);

        let event_handle = &mut borrow_global_mut<TokenListings<CoinType>>(signer::address_of(token_owner)).listing_events;
        event::emit_event<TokenListingEvent>(
            event_handle,
            TokenListingEvent {
                token_id,
                amount: token_amount,
                coin_type_info: type_info::type_of<CoinType>(),
            },
        );
    }

    /// Initalize the token listing for a token owner
    fun initialize_token_listing<CoinType>(token_owner: &signer) {
        let addr = signer::address_of(token_owner);
        if ( !exists<TokenListings<CoinType>>(addr) ) {
            let token_listing = TokenListings<CoinType>{
                listings: table::new<TokenId, TokenCoinVault<CoinType>>(),
                listing_events: event::new_event_handle<TokenListingEvent>(token_owner),
                vault_events: event::new_event_handle<TokenVaultEvent>(token_owner),

            };
            move_to(token_owner, token_listing);
        }
    }

    /// Intialize the token escrow
    fun initialize_token_store_escrow(token_owner: &signer) {
        let addr = signer::address_of(token_owner);
        if ( !exists<TokenStoreEscrow>(addr) ) {
            let token_store_escrow = TokenStoreEscrow{
                token_escrows: table::new<TokenId, TokenEscrow>()
            };
            move_to(token_owner, token_store_escrow);
        }
    }

    /// Put the token into escrow that cannot be transferred or withdrawed by the owner.
    public fun deposit_token_to_escrow(
        token_owner: &signer,
        token_id: TokenId,
        tokens: Token,
    ) acquires TokenStoreEscrow {
        let tokens_in_escrow = &mut borrow_global_mut<TokenStoreEscrow>(
            signer::address_of(token_owner)).token_escrows;
        if (table::contains(tokens_in_escrow, token_id)) {
            let dst = &mut table::borrow_mut(tokens_in_escrow, token_id).token;
            merge(dst, tokens);
        } else {
            let token_escrow = TokenEscrow{
                token: tokens,
            };
            table::add(tokens_in_escrow, token_id, token_escrow);
        };
    }

    /// Private function for withdraw tokens from an escrow stored in token owner address
    fun withdraw_token_from_escrow_internal(
        token_owner_addr: address,
        token_id: TokenId,
        amount: u64
    ): Token acquires TokenStoreEscrow {
        let tokens_in_escrow = &mut borrow_global_mut<TokenStoreEscrow>(token_owner_addr).token_escrows;
        assert!(table::contains(tokens_in_escrow, token_id), ETOKEN_NOT_IN_ESCROW);
        let token_escrow = table::borrow_mut(tokens_in_escrow, token_id);
        split(&mut token_escrow.token, amount)
    }

    /// Withdraw tokens from the token escrow. It needs a signer to authorize
    public fun withdraw_token_from_escrow(
        token_owner: &signer,
        token_id: TokenId,
        amount: u64
    ): Token acquires TokenStoreEscrow {
        withdraw_token_from_escrow_internal(signer::address_of(token_owner), token_id, amount)
    }

    /// Cancel token listing for a fixed amount
    public fun cancel_token_listing<CoinType>(
        token_owner: &signer,
        token_id: TokenId,
        token_amount: u64
    ) acquires TokenListings, TokenStoreEscrow {
        let listing = &mut borrow_global_mut<TokenListings<CoinType>>(signer::address_of(token_owner)).listings;
        // remove the listing entry
        assert!(table::contains(listing, token_id), ETOKEN_LISTING_NOT_EXIST);
        table::remove(listing, token_id);
        // get token out of escrow and deposit back to owner token store
        let tokens = withdraw_token_from_escrow(token_owner, token_id, token_amount);
        deposit_token(token_owner, tokens);
    }

    #[test(token_owner = @0xAB, coin_owner = @0x1, aptos_framework = @aptos_framework)]
    public entry fun test_escrow_coin_for_token(token_owner: signer, coin_owner: signer, aptos_framework: signer) acquires TokenStoreEscrow, TokenListings {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test(10000000);
        let token_id = token_v1::create_collection_and_token(&token_owner, 100, 100, 100);
        token_v1::initialize_token_store(&coin_owner);
        coin::create_fake_money(&coin_owner, &token_owner, 100);

        list_token_for_vault<coin::FakeMoney>(&token_owner, token_id, 100, 1, 0);
        // coin owner only has 50 coins left
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(&coin_owner)) == 50, 1);
        // all tokens in token escrow or transferred. Token owner has 0 token in token_store
        assert!(token_v1::balance_of(signer::address_of(&token_owner), token_id) == 0, 1);

        let token_listing = &borrow_global<TokenListings<coin::FakeMoney>>(signer::address_of(&token_owner)).listings;

        // completely sold, no listing left
        assert!(table::length(token_listing) == 1, 1);
        let token_coin_vault = table::borrow(token_listing, token_id);
        // sold 50 token only 50 tokens left
        assert!(token_coin_vault.token_amount == 50, token_coin_vault.token_amount);
    }
}
