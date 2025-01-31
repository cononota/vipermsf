# -*- coding: binary -*-
require 'redis'
require 'net/http'
require 'uri'
require 'oj'
module Msf::Module::Rpcredis
  attr_accessor :redis_client

  def self.init
    @@redis_client  = self.init_redis_client
    @@message_queue = "rpcviper"
  end

  def self.init_redis_client
    file = ::File.join(Msf::Config.config_directory, 'redis.yml')

    begin
      if ::File.exist? file
        conf   = YAML.load(::File.read(file))['production']
        redis_client = Redis.new(host: conf['host'], password: conf['password'], port: conf['port'], db: conf['db'])
      else
        redis_client = Redis.new(host: "127.0.0.1", password: 'foobared', port: 6379, db: 5)
      end
      return redis_client
    rescue => e
      print_error("There was an error init redis: #{e.message}.", e)
    end
  end

  def pub_json_result(status = nil, message = nil, data = nil, uuid = nil)
    result           = {}
    result[:uuid]    = uuid
    result[:status]  = status
    result[:message] = message
    result[:data]    = data
    json             = Oj.generate(result)

    flag = @@redis_client.publish "MSF_RPC_RESULT_CHANNEL", json
    print("#{json}")
  end

  def pub_json_data(status = nil, message = nil, data = nil, uuid = nil)
    result           = {}
    result[:uuid]    = uuid
    result[:status]  = status
    result[:message] = message
    result[:data]    = data
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_DATA_CHANNEL", json
  end

  def self.pub_heartbeat_data(status = nil, type = nil, data = nil)
    result          = {}
    result[:status] = status
    result[:type]   = type
    result[:data]   = data
    json            = Oj.generate(result)
    flag            = @@redis_client.publish "MSF_RPC_HEARTBEAT_CHANNEL", json
  end

  def pub_console_print(prompt = nil, message = nil)
    result           = {}
    result[:prompt]  = prompt
    result[:message] = message
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_CONSOLE_PRINT", json
  end

  def print_good_redis(content)
    result           = {}
    result[:level]   = 0
    result[:content] = content
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_LOG_CHANNEL", json

  end

  def print_status_redis(content)
    result           = {}
    result[:level]   = 1
    result[:content] = content
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_LOG_CHANNEL", json
  end

  def print_warning_redis(content)
    result           = {}
    result[:level]   = 2
    result[:content] = content
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_LOG_CHANNEL", json
  end

  def print_error_redis(content)
    result           = {}
    result[:level]   = 3
    result[:content] = content
    json             = Oj.generate(result)
    flag             = @@redis_client.publish "MSF_RPC_LOG_CHANNEL", json
  end

  def redis_rpc_call(method_name, timeout = 0.5, **kwargs)
    # request setup
    function_call   = { 'function' => method_name.to_s, 'kwargs' => kwargs }
    response_queue  = @@message_queue + ':rpc:' + Rex::Text.rand_text_alpha(32)
    rpc_request     = { 'function_call' => function_call, 'response_queue' => response_queue }
    rpc_raw_request = Oj.generate(rpc_request)

    # transport
    @@redis_client.rpush @@message_queue, rpc_raw_request
    # message_queue, rpc_raw_response = @@redis_client.blpop response_queue, @@timeout
    message_queue, rpc_raw_response = @@redis_client.blpop response_queue, timeout
    if rpc_raw_response.nil?
      @@redis_client.lrem @@message_queue, 0, rpc_raw_request
      return
    end
    # response handling
    rpc_response = Oj.load(rpc_raw_response)
    return rpc_response
  end

  # Raises an Msf::RPC Exception.
  #
  # @param [Integer] code The error code to raise.
  # @param [String] message The error message.
  # @raise [Msf::RPC::Exception]
  # @return [void]
  def error(code, message)
    raise Msf::RPC::Exception.new(code, message)
  end
end


