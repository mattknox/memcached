
require "#{File.dirname(__FILE__)}/../test_helper"
require 'socket'
require 'mocha'
require 'benchmark'

class MemcachedTest < Test::Unit::TestCase

  def setup
    @servers = ['localhost:43042', 'localhost:43043']

    # Maximum allowed prefix key size for :hash_with_prefix_key_key => false
    @prefix_key = 'prefix_key_'

    @options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :distribution => :modula
    }
    @cache = Memcached.new(@servers, @options)

    @udp_options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :udp => true,
      :distribution => :modula
    }
    @udp_cache = Memcached.new(@servers, @udp_options)

    @nb_options = {
      :prefix_key => @prefix_key,
      :no_block => true,
      :buffer_requests => true,
      :hash => :default
    }
    @nb_cache = Memcached.new(@servers, @nb_options)

    @value = OpenStruct.new(:a => 1, :b => 2, :c => GenericClass)
    @marshalled_value = Marshal.dump(@value)
  end

  # Initialize

  def test_initialize
    cache = Memcached.new @servers, :prefix_key => 'test'
    assert_equal 'test', cache.options[:prefix_key]
    assert_equal 2, cache.send(:server_structs).size
    assert_equal 'localhost', cache.send(:server_structs).first.hostname
    assert_equal 'localhost', cache.send(:server_structs).last.hostname
    assert_equal 43043, cache.send(:server_structs).last.port
  end

  def test_initialize_with_ip_addresses
    cache = Memcached.new ['127.0.0.1:43042', '127.0.0.1:43043']
    assert_equal '127.0.0.1', cache.send(:server_structs).first.hostname
    assert_equal '127.0.0.1', cache.send(:server_structs).last.hostname
  end

  def test_initialize_without_port
    cache = Memcached.new ['localhost']
    assert_equal 'localhost', cache.send(:server_structs).first.hostname
    assert_equal 11211, cache.send(:server_structs).first.port
  end

  def test_initialize_with_ports_and_weights
    cache = Memcached.new ['localhost:43042:2', 'localhost:43043:10']
    assert_equal 2, cache.send(:server_structs).first.weight
    assert_equal 43043, cache.send(:server_structs).last.port
    assert_equal 10, cache.send(:server_structs).last.weight
  end

  def test_initialize_with_hostname_only
    addresses = (1..8).map { |i| "app-cache-%02d" % i }
    cache = Memcached.new(addresses)
    addresses.each_with_index do |address, index|
      assert_equal address, cache.send(:server_structs)[index].hostname
      assert_equal 11211, cache.send(:server_structs)[index].port
    end
  end

  def test_initialize_with_ip_address_and_options
    cache = Memcached.new '127.0.0.1:43042', :ketama_weighted => false
    assert_equal '127.0.0.1', cache.send(:server_structs).first.hostname
    assert_equal false, cache.options[:ketama_weighted]
  end

  def test_options_are_set
    Memcached::DEFAULTS.merge(@nb_options).each do |key, expected|
      value = @nb_cache.options[key]
      unless key == :rcv_timeout or key == :poll_timeout
        assert(expected == value, "#{key} should be #{expected} but was #{value}")
      end
    end
  end

  def test_options_are_frozen
    assert_raise(TypeError) do
      @cache.options[:no_block] = true
    end
  end

  def test_behaviors_are_set
    Memcached::BEHAVIORS.keys.each do |key, value|
      assert_not_nil @cache.send(:get_behavior, key)
    end
  end

  def test_initialize_with_invalid_server_strings
    assert_raise(ArgumentError) { Memcached.new ":43042" }
    assert_raise(ArgumentError) { Memcached.new "localhost:memcached" }
    assert_raise(ArgumentError) { Memcached.new "local host:43043:1" }
  end

#  def test_initialize_with_resolvable_hosts
#    host = `hostname`.chomp
#    cache = Memcached.new("#{host}:43042")
#    assert_equal host, cache.send(:server_structs).first.hostname
#
#    cache.set(key, @value)
#    assert_equal @value, cache.get(key)
#  end

  def test_initialize_with_invalid_options
    assert_raise(ArgumentError) do
      Memcached.new @servers, :sort_hosts => true, :distribution => :consistent
    end
  end

  def test_initialize_with_invalid_prefix_key
    assert_raise(ArgumentError) do
      Memcached.new @servers, :prefix_key => "x" * 128
    end
  end

  def test_initialize_without_prefix_key
    cache = Memcached.new @servers
    assert_equal nil, cache.options[:prefix_key]
    assert_equal 2, cache.send(:server_structs).size
  end

  def test_initialize_negative_behavior
    cache = Memcached.new @servers,
      :buffer_requests => false
    assert_nothing_raised do
      cache.set key, @value
    end
  end

  def test_initialize_without_backtraces
    cache = Memcached.new @servers,
      :show_backtraces => false
    cache.delete key rescue
    begin
      cache.get key
    rescue Memcached::NotFound => e
      assert e.backtrace.empty?
    end
  end

  def test_initialize_with_backtraces
    cache = Memcached.new @servers,
      :show_backtraces => true
    cache.delete key rescue
    begin
      cache.get key
    rescue Memcached::NotFound => e
      assert !e.backtrace.empty?
    end
  end

  def test_initialize_sort_hosts
    # Original
    cache = Memcached.new(@servers.sort,
      :sort_hosts => false,
      :distribution => :modula
    )
    assert_equal @servers.sort,
      cache.servers

    # Original with sort_hosts
    cache = Memcached.new(@servers.sort,
      :sort_hosts => true,
      :distribution => :modula
    )
    assert_equal @servers.sort,
      cache.servers

    # Reversed
    cache = Memcached.new(@servers.sort.reverse,
      :sort_hosts => false,
      :distribution => :modula
    )
      assert_equal @servers.sort.reverse,
    cache.servers

    # Reversed with sort_hosts
    cache = Memcached.new(@servers.sort.reverse,
      :sort_hosts => true,
      :distribution => :modula
    )
    assert_equal @servers.sort,
      cache.servers
  end

  def test_initialize_single_server
    cache = Memcached.new 'localhost:43042'
    assert_equal nil, cache.options[:prefix_key]
    assert_equal 1, cache.send(:server_structs).size
  end

  def test_initialize_strange_argument
    assert_raise(ArgumentError) { Memcached.new 1 }
  end

  # Get

  def test_get
    @cache.set key, @value
    result = @cache.get key
    assert_equal @value, result
  end
  
  def test_udp_get
    @udp_cache.set key, @value
    result = @udp_cache.get key
    assert_equal @value, result
  end  

  def test_get_nil
    @cache.set key, nil, 0
    result = @cache.get key
    assert_equal nil, result
  end

  def test_get_missing
    @cache.delete key rescue nil
    assert_raise(Memcached::NotFound) do
      result = @cache.get key
    end
  end

  def test_get_with_server_timeout
    socket = stub_server 43047
    cache = Memcached.new("localhost:43047:1", :timeout => 0.5)
    assert 0.49 < (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real

    cache = Memcached.new("localhost:43047:1", :poll_timeout => 0.001, :rcv_timeout => 0.5)
    assert 0.49 < (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real

    cache = Memcached.new("localhost:43047:1", :poll_timeout => 0.25, :rcv_timeout => 0.25)
    assert 0.51 > (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real
  end

  def test_get_with_no_block_server_timeout
    socket = stub_server 43048
    cache = Memcached.new("localhost:43048:1", :no_block => true, :timeout => 0.25)
    assert 0.24 < (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real

    cache = Memcached.new("localhost:43048:1", :no_block => true, :poll_timeout => 0.25, :rcv_timeout => 0.001)
    assert 0.24 < (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real

    cache = Memcached.new("localhost:43048:1", :no_block => true,
      :poll_timeout => 0.001,
      :rcv_timeout => 0.25 # No affect in no-block mode
    )
    assert 0.24 > (Benchmark.measure do
      assert_raise(Memcached::ATimeoutOccurred) do
        result = cache.get key
      end
    end).real
  end

  def test_get_with_prefix_key
    # Prefix_key
    cache = Memcached.new(
      # We can only use one server because the key is hashed separately from the prefix key
      @servers.first,
      :prefix_key => @prefix_key,
      :hash => :default,
      :distribution => :modula
    )
    cache.set key, @value
    assert_equal @value, cache.get(key)

    # No prefix_key specified
    cache = Memcached.new(
      @servers.first,
      :hash => :default,
      :distribution => :modula
    )
    assert_nothing_raised do
      assert_equal @value, cache.get("#{@prefix_key}#{key}")
    end
  end

  def test_values_with_null_characters_are_not_truncated
    value = OpenStruct.new(:a => Object.new) # Marshals with a null \000
    @cache.set key, value
    result = @cache.get key, false
    non_wrapped_result = Rlibmemcached.memcached_get(
      @cache.instance_variable_get("@struct"),
      key
    ).first
    assert result.size > non_wrapped_result.size
  end

  def test_get_multi
    @cache.set "#{key}_1", 1
    @cache.set "#{key}_2", 2
    assert_equal({"#{key}_1" => 1, "#{key}_2" => 2},
      @cache.get(["#{key}_1", "#{key}_2"]))
  end

  def test_get_multi_missing
    @cache.set "#{key}_1", 1
    @cache.delete "#{key}_2" rescue nil
    @cache.set "#{key}_3", 3
    @cache.delete "#{key}_4" rescue nil
    assert_equal(
      {"test_get_multi_missing_3"=>3, "test_get_multi_missing_1"=>1},
      @cache.get(["#{key}_1", "#{key}_2",  "#{key}_3",  "#{key}_4"])
     )
  end

  def test_get_multi_completely_missing
    @cache.delete "#{key}_1" rescue nil
    @cache.delete "#{key}_2" rescue nil
    assert_equal(
      {},
      @cache.get(["#{key}_1", "#{key}_2"])
     )
  end

  def test_set_and_get_unmarshalled
    @cache.set key, @value
    result = @cache.get key, false
    assert_equal @marshalled_value, result
  end

  def test_get_multi_unmarshalled
    @cache.set "#{key}_1", 1, 0, false
    @cache.set "#{key}_2", 2, 0, false
    assert_equal(
      {"#{key}_1" => "1", "#{key}_2" => "2"},
      @cache.get(["#{key}_1", "#{key}_2"], false)
    )
  end

  def test_get_multi_mixed_marshalling
    @cache.set "#{key}_1", 1
    @cache.set "#{key}_2", 2, 0, false
    assert_nothing_raised do
      @cache.get(["#{key}_1", "#{key}_2"], false)
    end
    assert_raise(ArgumentError) do
      @cache.get(["#{key}_1", "#{key}_2"])
    end
  end

  def test_get_with_random_distribution
    cache = Memcached.new(@servers, :distribution => :random)
    cache.set key, @value
    
    hits = (0..10).to_a.map do
      begin
        cache.get(key)
      rescue Memcached::NotFound
      end
    end.compact.size

    assert 0 < hits
    assert 10 > hits
  end

  # Set

  def test_set
    assert_nothing_raised do
      @cache.set(key, @value)
    end
  end

  def test_udp_set
    assert_nothing_raised do
      @udp_cache.set(key, @value)
    end
  end

  def test_set_expiry
    @cache.set key, @value, 1
    assert_nothing_raised do
      @cache.get key
    end
    sleep(2)
    assert_raise(Memcached::NotFound) do
      @cache.get key
    end
  end

  def test_set_with_default_ttl
    cache = Memcached.new(
      @servers,
      :default_ttl => 1
    )
    cache.set key, @value
    assert_nothing_raised do
      cache.get key
    end
    sleep(2)
    assert_raise(Memcached::NotFound) do
      cache.get key
    end
  end

  # Delete

  def test_delete
    @cache.set key, @value
    @cache.delete key
    assert_raise(Memcached::NotFound) do
      @cache.get key
    end
  end

  def test_missing_delete
    @cache.delete key rescue nil
    assert_raise(Memcached::NotFound) do
      @cache.delete key
    end
  end

  # Flush

  def test_flush
    @cache.set key, @value
    assert_equal @value,
      @cache.get(key)
    @cache.flush
    assert_raise(Memcached::NotFound) do
      @cache.get key
    end
  end

  # Add

  def test_add
    @cache.delete key rescue nil
    @cache.add key, @value
    assert_equal @value, @cache.get(key)
  end

  def test_existing_add
    @cache.set key, @value
    assert_raise(Memcached::NotStored) do
      @cache.add key, @value
    end
  end

  def test_add_expiry
    @cache.delete key rescue nil
    @cache.set key, @value, 1
    assert_nothing_raised do
      @cache.get key
    end
    sleep(1)
    assert_raise(Memcached::NotFound) do
      @cache.get key
    end
  end

  def test_unmarshalled_add
    @cache.delete key rescue nil
    @cache.add key, @marshalled_value, 0, false
    assert_equal @marshalled_value, @cache.get(key, false)
    assert_equal @value, @cache.get(key)
  end

  # Increment and decrement

  def test_increment
    @cache.set key, 10, 0, false
    assert_equal 11, @cache.increment(key)
  end

  def test_increment_offset
    @cache.set key, 10, 0, false
    assert_equal 15, @cache.increment(key, 5)
  end

  def test_missing_increment
    @cache.delete key rescue nil
    assert_raise(Memcached::NotFound) do
      @cache.increment key
    end
  end

  def test_decrement
    @cache.set key, 10, 0, false
    assert_equal 9, @cache.decrement(key)
  end

  def test_decrement_offset
    @cache.set key, 10, 0, false
    assert_equal 5, @cache.decrement(key, 5)
  end

  def test_missing_decrement
    @cache.delete key rescue nil
    assert_raise(Memcached::NotFound) do
      @cache.decrement key
    end
  end

  # Replace

  def test_replace
    @cache.set key, nil
    assert_nothing_raised do
      @cache.replace key, @value
    end
    assert_equal @value, @cache.get(key)
  end

  def test_missing_replace
    @cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @cache.replace key, @value
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @cache.get(key)
    end
  end

  # Append and prepend

  def test_append
    @cache.set key, "start", 0, false
    assert_nothing_raised do
      @cache.append key, "end"
    end
    assert_equal "startend", @cache.get(key, false)
  end

  def test_missing_append
    @cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @cache.append key, "end"
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @cache.get(key)
    end
  end

  def test_prepend
    @cache.set key, "end", 0, false
    assert_nothing_raised do
      @cache.prepend key, "start"
    end
    assert_equal "startend", @cache.get(key, false)
  end

  def test_missing_prepend
    @cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @cache.prepend key, "end"
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @cache.get(key)
    end
  end

  def test_cas
    cache = Memcached.new(
      @servers,
      :prefix_key => @prefix_key,
      :support_cas => true
    )
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)

    # Existing set
    cache.set key, @value
    cache.cas(key) do |current|
      assert_equal @value, current
      value2
    end
    assert_equal value2, cache.get(key)

    # Existing test without marshalling
    cache.set(key, "foo", 0, false)
    cache.cas(key, 0, false) do |current|
      "#{current}bar"
    end
    assert_equal "foobar", cache.get(key, false)

    # Missing set
    cache.delete key
    assert_raises(Memcached::NotFound) do
      cache.cas(key) {}
    end

    # Conflicting set
    cache.set key, @value
    assert_raises(Memcached::ConnectionDataExists) do
      cache.cas(key) do |current|
        cache.set key, value2
        current
      end
    end
  end

  # Error states

  def test_key_with_spaces
    key = "i have a space"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end
  end

  def test_key_with_null
    key = "with\000null"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end

    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      response = @cache.get([key])
    end
  end

  def test_key_with_invalid_control_characters
    key = "ch\303\242teau"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end

    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      response = @cache.get([key])
    end
  end

  def test_key_too_long
    key = "x"*251
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end

    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get([key])
    end
  end

  def test_server_error_message
    @cache.set key, "I'm big" * 1000000
    assert false # Never reached
  rescue Memcached::ServerError => e
    assert_match /^"object too large for cache". Key/, e.message
  end
  
  def test_errno_message
    Rlibmemcached::MemcachedServerSt.any_instance.expects("cached_errno").returns(1)
    @cache.send(:check_return_code, Rlibmemcached::MEMCACHED_ERRNO, key)    
  rescue Memcached::SystemError => e
    assert_match /^Errno 1: "Operation not permitted". Key/, e.message
  end

  # Stats

  def test_stats
    stats = @cache.stats
    assert_equal 2, stats[:pid].size
    assert_instance_of Fixnum, stats[:pid].first
    assert_instance_of String, stats[:version].first
  end

  # Clone

  def test_clone
    cache = @cache.clone
    assert_equal cache.servers, @cache.servers
    assert_not_equal cache, @cache

    # Definitely check that the structs are unlinked
    assert_not_equal @cache.instance_variable_get('@struct').object_id,
      cache.instance_variable_get('@struct').object_id

    assert_nothing_raised do
      @cache.set key, @value
    end
  end

  # Non-blocking IO

  def test_buffered_requests_return_value
    cache = Memcached.new @servers,
      :buffer_requests => true
    assert_nothing_raised do
      cache.set key, @value
    end
    ret = Rlibmemcached.memcached_set(
      cache.instance_variable_get("@struct"),
      key,
      @marshalled_value,
      0,
      Memcached::FLAGS
    )
    assert_equal Rlibmemcached::MEMCACHED_BUFFERED, ret
  end

  def test_no_block_return_value
    assert_nothing_raised do
      @nb_cache.set key, @value
    end
    ret = Rlibmemcached.memcached_set(
      @nb_cache.instance_variable_get("@struct"),
      key,
      @marshalled_value,
      0,
      Memcached::FLAGS
    )
    assert_equal Rlibmemcached::MEMCACHED_BUFFERED, ret
  end
  
  def test_no_block_get
    @nb_cache.set key, @value
    assert_equal @value, 
      @nb_cache.get(key)
  end

  def test_no_block_missing_delete
    @nb_cache.delete key rescue nil
    assert_nothing_raised do
      @nb_cache.delete key
    end
  end

  def test_no_block_set_invalid_key
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @nb_cache.set "I'm so bad", @value
    end
  end

  def test_no_block_set_object_too_large
    assert_nothing_raised do
      @nb_cache.set key, "I'm big" * 1000000
    end
  end

  def test_no_block_existing_add
    # Should still raise
    @nb_cache.set key, @value
    assert_raise(Memcached::NotStored) do
      @nb_cache.add key, @value
    end
  end

  # Server removal and consistent hashing

  def test_missing_server
    socket = stub_server 43041  
    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 1,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5
    )

    # Hit first server
    key1 = 'test_missing_server6'
    cache.set(key1, @value)
    assert_equal cache.get(key1), @value

    # Hit second server
    key2 = 'test_missing_server'
    assert_raise(Memcached::ATimeoutOccurred) do
      cache.set(key2, @value)
    end

    # Hit second server again
    key2 = 'test_missing_server'
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    # Hit first server on retry
    assert_nothing_raised do
      cache.set(key2, @value)
      cache.get(key2)
    end
    
    sleep(2)
    
    # Hit second server again after restore, expect same failure
    key2 = 'test_missing_server'
    assert_raise(Memcached::UnknownReadFailure) do
      cache.set(key2, @value)
    end        
  end

  def test_consistent_hashing

    keys = %w(EN6qtgMW n6Oz2W4I ss4A8Brr QShqFLZt Y3hgP9bs CokDD4OD Nd3iTSE1 24vBV4AU H9XBUQs5 E5j8vUq1 AzSh8fva PYBlK2Pi Ke3TgZ4I AyAIYanO oxj8Xhyd eBFnE6Bt yZyTikWQ pwGoU7Pw 2UNDkKRN qMJzkgo2 keFXbQXq pBl2QnIg ApRl3mWY wmalTJW1 TLueug8M wPQL4Qfg uACwus23 nmOk9R6w lwgZJrzJ v1UJtKdG RK629Cra U2UXFRqr d9OQLNl8 KAm1K3m5 Z13gKZ1v tNVai1nT LhpVXuVx pRib1Itj I1oLUob7 Z1nUsd5Q ZOwHehUa aXpFX29U ZsnqxlGz ivQRjOdb mB3iBEAj)

    # Five servers
    cache = Memcached.new(
      @servers + ['localhost:43044', 'localhost:43045', 'localhost:43046'],
      :prefix_key => @prefix_key
    )

    cache.flush
    keys.each do |key|
      cache.set(key, @value)
    end

    # Pull a server
    cache = Memcached.new(
      @servers + ['localhost:43044', 'localhost:43046'],
      :prefix_key => @prefix_key
    )

    failed = 0
    keys.each_with_index do |key, i|
      begin
        cache.get(key)
      rescue Memcached::NotFound
        failed += 1
      end
    end

    assert(failed < keys.size / 3, "#{failed} failed out of #{keys.size}")
  end

  # Concurrency

  def test_thread_contention
    threads = []
    4.times do |index|
      threads << Thread.new do
        cache = @cache.clone
        assert_nothing_raised do
          cache.set("test_thread_contention_#{index}", index)
        end
        assert_equal index, cache.get("test_thread_contention_#{index}")
      end
    end
    threads.each {|thread| thread.join}
  end
  
  # Hash  
  
  def test_hash
    assert_equal 3157003241, 
      Rlibmemcached.memcached_generate_hash_rvalue("test", Rlibmemcached::MEMCACHED_HASH_FNV1_32)
  end  

  # Memory cleanup

  def test_reset
    original_struct = @cache.instance_variable_get("@struct")
    assert_nothing_raised do
      @cache.reset
    end
    assert_not_equal original_struct,
      @cache.instance_variable_get("@struct")
  end

  private

  def key
    caller.first[/`(.*)'/, 1] # '
  end

  def stub_server(port)
    socket = TCPServer.new('127.0.0.1', port)
    Thread.new { socket.accept }
    socket
  end

end

