require 'socket'
require 'test/unit'
require 'base64'
require 'timeout'

if RUBY_VERSION < "2.3.0"
  puts "You need at least ruby version 2.3.0; see https://rvm.io/"
  exit 1
end

Thread.abort_on_exception = true
STDOUT.sync = true

class StackTest < Test::Unit::TestCase
  def setup
    @thread_pool = []
  end

  def teardown
    @thread_pool.each do |t|
      next if !t.alive?
      (t[:socket].shutdown rescue t[:socket].close) if t[:socket]
      t.kill
      t.join
    end
  end

  #
  # issues one push and one pop
  #
  def test_single_request
    puts "test_single_request"
    s = random_string
    pr = push(s)
    assert_equal(0, pr, "expected 0, got #{pr}")
    r = pop()
    assert_equal(s, r, "expected #{s}, got #{r}")
  end

  #
  # issues N pushes, then N pops.
  #
  def test_serialized_requests
    puts "test_serialized_requests"
    30.times do
      ntimes = rand(10)
      expects = []
      ntimes.times do
        expects << random_string
        pr = push(expects[-1])
        assert_equal(0, pr, "expected 0, got #{pr}")
      end

      ntimes.times do
        r = pop
        s = expects.pop
        assert_equal(s, r, "expected #{s}, got #{r}")
      end
    end
  end

  #
  # issues 100 pushes, then 100 pops; a number of times
  #
  def test_full_stack_push_and_pop
    puts "test_full_stack_push_and_pop"
    (rand(10) + 2).times do
      expects = []
      100.times do
        expects << random_string
        pr = push(expects[-1])
        assert_equal(0, pr, "expected 0, got #{pr}")
      end

      100.times do
        r = pop
        s = expects.pop
        assert_equal(s, r, "expected #{s}, got #{r}")
      end
    end
  end

  #
  # randomly interleaves pushes and pops, expects pops to be handled in
  # reverse order of the pushes.
  #
  # to avoid race conditions, we impose a strict ordering between pushes and
  # pops and track, internally, the state in which we believe the server to
  # be.
  #
  # avoid a scenario in which we attempt a push on an empty stack; that will
  # cause the client to deadlock.
  #
  def test_interleaved_requests
    puts "test_interleaved_requests"
    30.times do
      mutex = Mutex.new
      ntimes = rand(50)
      stack = []

      t = Thread.new do
        ntimes.times do
          while stack.empty?
            sleep(0.05)
          end

          r, s = nil, nil
          mutex.synchronize do
            r = pop
            s = stack.pop
          end
          assert_equal(s, r, "expected #{s}, got #{r}")
          sleep(rand(3) / 100.0) if rand(2).zero?
        end
        mutex.unlock if mutex.owned?
      end

      ntimes.times do
        mutex.synchronize do
          stack << random_string
          pr = push(stack[-1])
          assert_equal(0, pr, "expected 0, got #{pr}")
        end
        sleep(rand(3) / 100.0) if rand(2).zero?
      end
      mutex.unlock if mutex.owned?

      t.join
    end
  end

  #
  # fires off a pop, waits 2 seconds, then issues the push that the pop should
  # get.
  #
  def test_long_polling_get
    puts "test_long_polling_get"
    s = random_string
    t = Thread.new do
      r = pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end

    sleep 2
    pr = push(s)
    assert_equal(0, pr, "expected 0, got #{pr}")
    t.join
  end

  #
  # fills up the stack with 100 entries; issues a long polling push. pops one
  # item off the stack, then verifies that the long polling push completes
  # correctly.
  #
  def test_long_polling_push
    puts "test_long_polling_push"
    s1 = nil
    100.times do
      s1 = random_string
      pr = push(s1)
      assert_equal(0, pr, "expected 0, got #{pr}")
    end

    # start the long polling push
    s2 = random_string
    t = Thread.new do
      pr = push(s2)
      assert_equal(0, pr, "expected 0, got #{pr}")
    end
    sleep 2

    r1 = pop
    assert_equal(s1, r1, "expected #{s1}, got #{r1}")

    # now the long polling push should succeed
    r2 = pop
    assert_equal(s2, r2, "expected #{s2}, got #{r2}")
    t.join

    99.times do
      pop
    end
  end

  #
  # issues a whole bunch of pops that should all block. They all time out,
  # which should clean up state in the server. Then a regular push/pop should
  # succeed.
  #
  def test_pops_to_empty_stack
    puts "test_pops_to_empty_stack"
    threads = []
    100.times do
      threads << Thread.new do
        r = pop(:timeout => 2)
        assert_equal(nil, r, "expected nil, got #{r}")
      end
    end
    threads.each {|t| t.join}

    test_single_request
  end

  #
  # fills up the stack; then issues another push, which should block (because
  # the stack is full), it will time out, then the 100 pops should obtain the
  # objects on the full stack.
  #
  def test_full_stack_ignore
    puts "test_full_stack_ignore"
    expects = []
    100.times do
      expects << random_string
      pr = push(expects[-1])
      assert_equal(0, pr, "expected 0, got #{pr}")
    end

    (rand(5) + 2).times do
      r = push("too full", :timeout => 3)
      assert_equal(nil, r, "expected nil, got #{r}")
    end

    100.times do |i|
      r = pop
      s = expects.pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end
  end

  #
  # issue 100 very slow push requests. The next one should get a busy-byte
  #
  def test_server_resource_limit
    puts "test_server_resource_limit"
    start_slow_clients(nclients: 100)
    sleep 5

    (rand(6)+1).times do
      r = push(random_string)
      assert_equal(0xFF, r, "expected busy-state response")
    end
  end

  #
  # issue 100 simultaneous slow pushes. the 101st should work after the first
  # 100 have been marked as slow.
  #
  def test_slow_client_gets_killed_for_fast_client
    puts "test_slow_clients_get_killed_for_fast_client"
    start_slow_clients(nclients: 100)
    sleep 12
    test_single_request
  end

  #
  # issue 100 simultaneous slow pushes. only one should get killed for a full
  # 100-push-100-pop sequence to successfully complete
  #
  def test_one_slow_client_gets_killed_for_fast_clients
    puts "test_one_slow_client_gets_killed_for_fast_clients"
    start_slow_clients(nclients: 100)
    sleep 12
    test_full_stack_push_and_pop
  end

  #
  # test that the oldest client gets killed for a new one
  #
  def test_slowest_client_gets_killed
    puts "test_slowest_client_gets_killed"
    # start slow client
    r = nil
    t = Thread.new do
      r = push(random_string(15), :maxsend => 1, :sleep => 1)
    end
    sleep 3 # race condition, sort of, but meh

    # start another 99 slow clients for a string of 12 bytes; we expect these
    # to complete successfully, ie, 1 byte containing 0x00 response expected
    expects = start_slow_clients(nclients: 99, string_size: 12, push_responses: [0])
    sleep 8

    # should kill the oldest client
    test_single_request
    t.join
    assert_equal(nil, r, "expected nil, got #{r}")

    # ensure all 99 threads are done writing their string
    @thread_pool.each {|tx| tx.join}

    # don't care about the order, but do care about all strings being there
    99.times do
      r = pop
      assert(expects.include?(r), "expected #{r} to exist in expects[]")
      expects.delete(r)
    end
  end

  #
  # push 10 items,
  # start writing a push request, but die halfway through
  # pop 10 items
  #
  def test_server_survives_half_message
    puts "test_server_survives_half_message"

    expects = []
    10.times do
      expects << random_string
      pr = push(expects[-1])
      assert_equal(0, pr, "expected 0, got #{pr}")
    end

    s = random_string(15)
    header = s.length
    client = tcp_socket()
    nbytes = client.send([header].pack("C1"), 0)
    if nbytes != 1
      raise "push: header write failed"
    end

    client.send(s[0..3], 0)
    client.shutdown

    10.times do
      r = pop
      s = expects.pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end
  end


  #
  # push 10 items,
  # start writing a push request, stop halfway through
  # pop 5 items
  # finish writing the push request
  # pop that item
  # pop the remaining 5 items
  #
  def test_server_queues_slow_message_correctly
    puts "test_server_queues_slow_message_correctly"

    expects = []
    10.times do
      expects << random_string
      pr = push(expects[-1])
      assert_equal(0, pr, "expected 0, got #{pr}")
    end

    # send 1 byte of slow string
    slow_s = random_string(2)
    header = slow_s.length
    client = tcp_socket()
    nbytes = client.send([header].pack("C1"), 0)
    if nbytes != 1
      raise "push: header write failed"
    end

    client.send(slow_s[0], 0)

    5.times do
      r = pop
      s = expects.pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end

    # send second byte of slow string, pop it
    client.send(slow_s[1], 0)
    r = pop
    assert_equal(slow_s, r, "expected #{slow_s}, got #{r}")

    5.times do
      r = pop
      s = expects.pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end
  end

  def test_slow_clients_are_not_disconnected_for_no_reason
    puts "test_slow_clients_are_not_disconnected_for_no_reason"
    expects = []
    100.times do
      expects << random_string
      pr = push(expects[-1])
      assert_equal(0, pr, "expected 0, got #{pr}")
    end

    sleep 12
    100.times do
      r = pop
      s = expects.pop
      assert_equal(s, r, "expected #{s}, got #{r}")
    end
  end

protected

  def random_string(length = 8)
    Base64.encode64(Random.new.bytes(length)).strip[0..(length-1)]
  end

  def tcp_socket
    Thread.current[:socket] = TCPSocket.new("localhost", 8080)
  end

  #
  # performs a push of the given string.
  # optional arguments
  #
  # :timeout => timeout to the whole operation; does a close on timeout
  # :maxsend => send at most this many bytes in a send; default no limit
  # :sleep => sleep this much between each send; default no sleep
  #
  # an optional block passed to push() is invoked after each send()
  #
  def push(s, args = {})
    client = nil
    _push = proc do
      header = s.length
      client = tcp_socket()

      begin
        nbytes = client.send([header].pack("C1"), 0)
        if nbytes != 1
          raise "push: header write failed"
        end

        nbytes = 0
        maxsend = args[:maxsend] || s.length
        while nbytes < s.length
          bytes_left_to_send = s.length - nbytes
          nbytes_to_send = [bytes_left_to_send, maxsend].min
          substring_to_send = s[nbytes..(nbytes+nbytes_to_send-1)]
          nbytes += client.send(substring_to_send, 0)
          if block_given?
            yield
          end
          sleep(args[:sleep]) if args[:sleep]
        end
      rescue Errno::EPIPE, Errno::ECONNRESET
        #server might have been busy and closed the connection
      end

      r = nil
      begin
        r = client.recv(1).unpack("C1")[0]
      rescue Errno::EPIPE, Errno::ECONNRESET
        #server might have been busy and closed the connection
      end

      # maybe nil if the connection was killed
      if ![0xFF, 0, nil].include?(r)
        raise "invalid push response #{r.inspect}"
      end
      return r
    end

    r = nil
    if args[:timeout]
      begin
        Timeout::timeout(args[:timeout]) do
          r = _push.call
        end
      rescue Timeout::Error
      end
    else
      r = _push.call
    end

    return r
  ensure
    if !client.nil?
      client.close
    end
  end

  def pop(args = {})
    client = tcp_socket()

    _pop = proc do
      begin
        client.send([0x80].pack("C1"), 0)
      rescue Errno::EPIPE
        #server might have been busy and closed the connection
      end
      begin
        header = client.recv(1).unpack("C1")[0]
      rescue Errno::EPIPE, Errno::ECONNRESET
        return nil # If the server disconnects because it has been > 10s since start
      end
      # busy byte
      if (header == 0xFF)
        return 0xFF
      end

      # invalid pop response
      if ((header & 0x80) != 0)
        raise "invalid pop response #{header.inspect}"
      end

      payload_length = header & 0x7f
      payload = ""
      begin
        while payload.length < payload_length
          payload += client.recv(payload_length)
        end
      rescue Errno::EPIPE, Errno::ECONNRESET
        return nil # If the server disconnects because it has been > 10s since start
      end
      return payload
    end

    r = nil
    if args[:timeout]
      begin
        Timeout::timeout(args[:timeout]) do
          r = _pop.call
        end
      rescue Timeout::Error
      end
    else
      r = _pop.call
    end

    return r
  ensure
    if !client.nil?
      client.close
    end
  end

  def start_slow_clients(nclients: 100, string_size: 127, push_responses: [nil])
    mutex = Mutex.new
    count = 0
    expects = []
    nclients.times do
      @thread_pool << Thread.new do
        added_count = false
        s = random_string(string_size)
        expects << s
        pr = push(s, :maxsend => 1, :sleep => 1) do
          if !added_count
            mutex.synchronize { count += 1 }
            added_count = true
          end
        end
        assert(push_responses.include?(pr), "expected one of #{push_responses.inspect}, got #{pr}")
      end
    end

    # wait for all threads to have written at least 1 character
    while count != nclients
      sleep (0.01)
    end

    expects
  end
end