module titusvaults::Marketplace {
    use std::vector;
    use std::signer::address_of;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    // --- errors ---
    const EUNAUTHORIZED:u64 = 1;
    const EOPTION_EXPIRED: u64 = 2;
    const EOPTION_ALREADY_LISTED: u64 = 3;
    const EOPTION_DOES_NOT_EXIST: u64 = 4;
    const EINSUFFICIENT_PAYMENT: u64 = 5;
    const EOPTION_ALREADY_SOLD: u64 =  6;
    // tests errors
    const EINVALID_LISTING_COUNT: u64 = 1;
    const EINVALID_OPTION_CONTRACT_ID: u64 = 2;
    const EINVALID_PRICE: u64 = 3;

    // --- structs ---
    struct Listing has key, store, drop {
        option_contract_id: u64,
        price: u64,
        seller: address,
        expiry_date: u64,
        is_sold: bool
    }

    struct Listings has key {
        listings: vector<Listing>,
    }

    struct ListingParams has key, drop {
        option_contract_id: u64,
        price: u64,
        expiry_date: u64
    }

    // --- events ---
    #[event]
    struct ListOptionsEvent has drop, store {
        option_contract_id: u64,
        price: u64,
        seller: address,
    }

    #[event]
    struct BuyOptionsEvent has drop, store {
        option_contract_id: u64,
        price: u64,
        seller: address,
        buyer: address,
    }

    #[event]
    struct CancelListingEvent has drop, store {
        option_contract_id: u64,
        price: u64,
        seller: address,
    }

    // --- functions ---
    // init listing
    public entry fun initialize(_host: &signer) {
        let host_addr = address_of(_host);
        move_to(_host, Listings {
            listings: vector::empty<Listing>()
        });
    }

    // list options
    public (friend) fun list_options(_host: &signer, list_params: vector<ListingParams> ) acquires Listings {
        let sender = address_of(_host);

        let i = 0;
        let len = vector::length(&list_params);
        let param_price = 0;

        while ( i < len ) {
            let param = vector::borrow(&list_params, i);
            let current_time = timestamp::now_microseconds();

            // check if the option token has expired
            assert!(param.expiry_date > timestamp::now_microseconds(), EOPTION_EXPIRED);

            // check if the option is not already listed
            assert!(!is_option_listed(param.option_contract_id), EOPTION_ALREADY_LISTED);

            // new listing
            let new_listing = Listing {
                option_contract_id: param.option_contract_id,
                price: param.price,
                seller: sender,
                expiry_date: param.expiry_date,
                is_sold: false,
            };

            // add new listing to the listings
            let listings = borrow_global_mut<Listings>(@titusmarketplace);
            vector::push_back(&mut listings.listings, new_listing);

            param_price = param_price + param.price;

            i = i + 1;

            // list options event
            let list_options_event = ListOptionsEvent {
                option_contract_id: param.option_contract_id,
                price: param_price,
                seller: sender,
            };
            event::emit(list_options_event);
        };
    }

    // buy options
    public (friend) fun buy_options(buyer: &signer, option_contract_ids: vector<u64>, payment: Coin<AptosCoin>) acquires Listings  {
        let buyer = address_of(buyer);
        let i = 0;
        let len = vector::length(&option_contract_ids);
        let cost = 0;

        while ( i < len ) {
            let option_id = *vector::borrow(&option_contract_ids, i); 

            // check if the option already listed
            assert!(is_option_listed(option_id), EOPTION_DOES_NOT_EXIST);
       
            let listings = borrow_global_mut<Listings>(@titusmarketplace);
            let (listing, listing_index) = get_listing(listings, option_id);    

            // check if the option token has expired
            assert!(listing.expiry_date > timestamp::now_microseconds(), EOPTION_EXPIRED);

            // mark the option as sold
            listing.is_sold = true;

            cost = cost + listing.price;

            i = i + 1;

            // buy options event
            let buy_options_event = BuyOptionsEvent {
                option_contract_id: option_id,
                price: listing.price,
                seller: listing.seller,
                buyer: buyer,
            };
            event::emit(buy_options_event);
        };

        // ensure the buyer has sent enough payment
        assert!(coin::value(&payment) >= cost, EINSUFFICIENT_PAYMENT);

        coin::deposit(@titusmarketplace, payment);
    }

    // cancel listing
    public (friend) fun cancel_listing(account: &signer, option_contract_ids: vector<u64>) acquires Listings {
        let sender = address_of(account);
        
        let i = 0;
        let len = vector::length(&option_contract_ids);
        
        while (i < len) {
            let option_id = *vector::borrow(&option_contract_ids, i);
            
            // check if the option already listed
            assert!(is_option_listed(option_id), EOPTION_DOES_NOT_EXIST);

            let listings = borrow_global_mut<Listings>(@titusmarketplace);
            let (listing, listing_index) = get_listing(listings, option_id); 
            let listing_price = listing.price;
            
            // check if the listing is not sold
            assert!(!listing.is_sold, EOPTION_ALREADY_SOLD);

            // check if the listing seller is the sender
            assert!(listing.seller == sender, EUNAUTHORIZED);

            vector::remove(&mut listings.listings, listing_index);

            // cancel listing event
            let cancel_listing_event = CancelListingEvent {
                option_contract_id: option_id,
                price: listing_price,
                seller: sender,
            };
            event::emit(cancel_listing_event);

            i = i + 1;
        };
    }

    // --- helper functions ---
    fun is_option_listed(option_contract_id: u64): bool acquires Listings {
        let listings = borrow_global<Listings>(@titusmarketplace);
        let i = 0;
        let len = vector::length(&listings.listings);
        
        while (i < len) {
            let listing = vector::borrow(&listings.listings, i);
            if (listing.option_contract_id == option_contract_id) {
                return true
            };
            i = i + 1;
        };
        
        false
    }
    
    fun get_listing(listings: &mut Listings, option_contract_id: u64): (&mut Listing, u64) {
        let i = 0;
        let len = vector::length(&listings.listings);
        
        while (i < len) {
            let listing = vector::borrow_mut(&mut listings.listings, i);
            if (listing.option_contract_id == option_contract_id) {
                return (listing, i)
            };
            i = i + 1;
        };

        abort EOPTION_DOES_NOT_EXIST
    }
    
    // --- tests ---
    #[test_only]
    use aptos_framework::account;
    use std::signer;

    #[test_only]
    fun setup() {
        
    }

    // test list options
    #[test(titusmarketplace = @titusmarketplace, user = @0x2, framework = @aptos_framework)]
    fun test_list_options(titusmarketplace: &signer, user: &signer, framework: &signer) acquires Listings {

        // Initialize Listings
        initialize(titusmarketplace);

        // set up test parameters
        let list_params = vector::empty<ListingParams>();
        let param1 = ListingParams { option_contract_id: 1, price: 100, expiry_date: 1000000000 };
        let param2 = ListingParams { option_contract_id: 2, price: 200, expiry_date: 1000000000 };
        vector::push_back(&mut list_params, param1);
        vector::push_back(&mut list_params, param2);

        // set current timestamp
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test(900000000);

        // list options
        list_options(user, list_params);

        let listings = borrow_global<Listings>(@titusmarketplace);

        // assert listings length
        assert!(vector::length(&listings.listings) == 2, EINVALID_LISTING_COUNT);

        let listing1 = vector::borrow(&listings.listings, 0);
        assert!(listing1.option_contract_id == 1, EINVALID_OPTION_CONTRACT_ID);
        assert!(listing1.price == 100, EINVALID_PRICE);

        let listing2 = vector::borrow(&listings.listings, 1);
        assert!(listing2.option_contract_id == 2, EINVALID_OPTION_CONTRACT_ID);
        assert!(listing2.price == 200, EINVALID_PRICE);
    }

    // test list options expired
    #[test(titusmarketplace = @titusmarketplace, user = @0x2, framework = @aptos_framework)]
    // expected failure because of timing restriction
    #[expected_failure(abort_code = EOPTION_EXPIRED)]
    fun test_list_options_expired(titusmarketplace: &signer, user: &signer, framework: &signer) acquires Listings {

        // Initialize Listings
        initialize(titusmarketplace);

        // set up test parameters
        let list_params = vector::empty<ListingParams>();
        let param = ListingParams { option_contract_id: 1, price: 100, expiry_date: 800000000 };
        vector::push_back(&mut list_params, param);

        // set current timestamp
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test(900000000);

        // list options
        list_options(user, list_params);
    }

    // test buy options
    #[test(titusmarketplace = @titusmarketplace, user = @0x2, framework = @aptos_framework)]
    fun test_buy_options(titusmarketplace: &signer, user: &signer, framework: &signer) acquires Listings {

        // Initialize Listings
        initialize(titusmarketplace);

        // set up test parameters
        let list_params = vector::empty<ListingParams>();
        let param = ListingParams { option_contract_id: 1, price: 100, expiry_date: 2000000000 };
        vector::push_back(&mut list_params, param);

        // set current timestamp
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test(800000000);

        // list options
        list_options(user, list_params);

        // add 100 coins to the user
        let user_addr = signer::address_of(user);
        let (burn, mint) = aptos_framework::aptos_coin::initialize_for_test(&account::create_signer_for_test(@0x1));
        aptos_framework::aptos_account::create_account(copy user_addr);
        let coin = coin::mint<AptosCoin>(1000, &mint);
        coin::deposit(copy user_addr, coin);

        let payment = coin::withdraw<AptosCoin>(user, 100);

        // buy options
        let options_contracts_ids = vector::empty<u64>();
        vector::push_back(&mut options_contracts_ids, 1);

        buy_options(user, options_contracts_ids, payment);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }
}