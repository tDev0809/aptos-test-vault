module TestVault::Escrow {
    use aptos_framework::coin as Coin;
    use aptos_std::event;
    use std::signer;

    const ECOIN_NOT_REGISTERED: u64 = 1;
    const EVAULT_ALREADY_MOVED: u64 = 2;
    const USER_NOT_DEPOSITED: u64 = 3;
    const BALANCE_NOT_ENOUGHT: u64 = 4;
    const ESCROW_PAUSED: u64 = 5;
    const INVALIED_ADMIN: u64 = 6;
    const INVALIED_ESCROW_ADDRESS: u64 = 7;

    struct Escrow<phantom CoinType> has key {
        vault: Coin::Coin<CoinType>,
        paused: bool
    }

    struct UserInfo<phantom CoinType> has key {
        amount: u64,
        message_change_events: event::EventHandle<MessageWithdrawDepositEvent>,
    }

    struct MessageWithdrawDepositEvent has drop, store {
        from_amount: u64,
        to_amount: u64,
    }

    public entry fun init_escrow<CoinType>(admin: &signer) {
        let addr = signer::address_of(admin);

        if (!Coin::is_account_registered<CoinType>(addr)) {
            Coin::register<CoinType>(admin);
        };

        assert!(Coin::is_account_registered<CoinType>(addr), ECOIN_NOT_REGISTERED);
        assert!(!exists<Escrow<CoinType>>(addr), EVAULT_ALREADY_MOVED);
        let vault = Coin::zero<CoinType>();
        move_to(admin, Escrow {
            vault,
            paused: false
        });
    }

    public entry fun pause_escrow<CoinType>(admin: &signer) acquires Escrow {
        let addr = signer::address_of(admin);
        assert!(exists<Escrow<CoinType>>(addr), INVALIED_ADMIN);

        let old_escrow = borrow_global_mut<Escrow<CoinType>>(addr);
        old_escrow.paused = true;
    }

    
    public entry fun resume_escrow<CoinType>(admin: &signer) acquires Escrow {
        let addr = signer::address_of(admin);
        assert!(exists<Escrow<CoinType>>(addr), INVALIED_ADMIN);

        let old_escrow = borrow_global_mut<Escrow<CoinType>>(addr);
        old_escrow.paused = false;
    }

    public entry fun deposit<CoinType>(user: &signer, amount: u64, escrow_account: address) acquires Escrow, UserInfo {
        assert!(!*&borrow_global<Escrow<CoinType>>(escrow_account).paused, ESCROW_PAUSED);

        let addr = signer::address_of(user);
        assert!(Coin::is_account_registered<CoinType>(addr), ECOIN_NOT_REGISTERED);
        if (!exists<UserInfo<CoinType>>(addr)) {
            move_to(user, UserInfo<CoinType> {
                amount: (copy amount),
                message_change_events: event::new_event_handle<MessageWithdrawDepositEvent>(copy user),
            });
        } else {
            let old_info = borrow_global_mut<UserInfo<CoinType>>(addr);
            let from_amount = *&old_info.amount;
            event::emit_event(&mut old_info.message_change_events, MessageWithdrawDepositEvent {
                from_amount,
                to_amount: from_amount + (copy amount),
            });
            old_info.amount = old_info.amount + (copy amount);
        };
        let coin = Coin::withdraw<CoinType>(user, amount);
        let escrow = borrow_global_mut<Escrow<CoinType>>(escrow_account);
        Coin::merge<CoinType>(&mut escrow.vault, coin);
    }

    public entry fun withdraw<CoinType>(user: &signer, amount: u64, escrow_account: address) acquires Escrow, UserInfo {
        assert!(!*&borrow_global<Escrow<CoinType>>(escrow_account).paused, ESCROW_PAUSED);

        let addr = signer::address_of(user);
        assert!(Coin::is_account_registered<CoinType>(addr), ECOIN_NOT_REGISTERED);
        assert!(exists<UserInfo<CoinType>>(addr), USER_NOT_DEPOSITED);

        let current_info = borrow_global_mut<UserInfo<CoinType>>(addr);
        let current_amount = *&current_info.amount;
        assert!(current_amount >= amount, BALANCE_NOT_ENOUGHT);

        event::emit_event(&mut current_info.message_change_events, MessageWithdrawDepositEvent {
            from_amount: current_amount,
            to_amount: current_amount - (copy amount),
        });
        current_info.amount = current_info.amount - (copy amount);

        let escrow = borrow_global_mut<Escrow<CoinType>>(escrow_account);
        let coins = Coin::extract<CoinType>(&mut escrow.vault, amount);
        Coin::deposit<CoinType>(addr, coins);
    } 

    public entry fun is_initialized_valut<CoinType>(escrow_account: address): bool {
        exists<Escrow<CoinType>>(escrow_account)
    }

    public entry fun get_vault_status<CoinType>(escrow_account: address): bool acquires Escrow {
        assert!(exists<Escrow<CoinType>>(escrow_account), INVALIED_ESCROW_ADDRESS);
        *&borrow_global<Escrow<CoinType>>(escrow_account).paused
    }

    public entry fun get_user_info<CoinType>(user_account: address): u64 acquires UserInfo {
        if (!exists<UserInfo<CoinType>>(user_account)) {
            return 0
        };

        *&borrow_global<UserInfo<CoinType>>(user_account).amount
    }
}