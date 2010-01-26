require 'digest/sha1'
require 'hmac-sha1'
#require 'openssl'

module Ohm
  class Model
    DIGEST  = OpenSSL::Digest::Digest.new('sha1')

    class << self      
      def get_by_key_name(key_name)
        hash = { :key_name => key_name }
        self.find(hash).first
      end

      def get_hash_key_name(value)
        'hash_' + sha1_hash(value)
      end

      def sha1_hash(value)
        Digest::SHA1.hexdigest(value)
      end

      def sha1_hmac(secret, data)        
        HMAC::SHA1.hexdigest(secret, data)
        #OpenSSL::HMAC.digest(DIGEST, secret, data)
      end
    end
  end
end