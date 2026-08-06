
require_relative 'spec_helper'

class ZoneReaderTest < Minitest::Test

  include Dnsruby

  def setup
    @zone_data = <<ZONEDATA
$TTL 3600
; Comment
 ; Comment with whitespace in front
@                   IN SOA    ns1.example.com. hostmaster.example.com. (
                                1993112101
                                10800
                                3600
                                604800
                                7200
                              )
                    IN NS     ns1.example.com.
                    IN NS     ns2.example.com.
                    IN MX     10 mx.example.com.
                    IN TXT    "v=spf1 mx ~all"
www                 IN A      192.0.2.10
                    IN AAAA   2001:DB8::10
ftp.example.com.    IN CNAME  www
db                  IN CNAME  www.example.com.
foo.example.com.    IN CAA    0 issue "ca.example.net; account=230123"
ZONEDATA

    @zone_file = Tempfile.new('zonefile')
    @zone_file << @zone_data
    @zone_file.flush
    @zone_file.rewind
    @reader = Dnsruby::ZoneReader.new("example.com.")
  end

  def teardown
    @zone_file.close
    @zone_file.unlink
  end

  def check_zone_data_is_valid(zone)
    assert_equal(1993112101, zone[0].serial)
    assert_equal("ns1.example.com.", zone[1].rdata)
    assert_equal("ns2.example.com.", zone[2].rdata)
    assert_equal("10 mx.example.com.", zone[3].rdata)
    assert_equal("\"v=spf1 mx ~all\"", zone[4].rdata)
    assert_equal("192.0.2.10", zone[5].rdata)
    assert_equal("2001:DB8::10", zone[6].rdata)
    assert_equal("www.example.com.", zone[7].rdata)
    assert_equal("www.example.com.", zone[8].rdata)
    assert_equal('0 issue "ca.example.net; account=230123"', zone[9].rdata)
  end

  def test_process_file_with_filename
    zone = @reader.process_file(@zone_file.path)
    check_zone_data_is_valid(zone)
  end

  def test_process_file_with_file_object
    zone = @reader.process_file(@zone_file)
    check_zone_data_is_valid(zone)
    assert_equal(false, @zone_file.closed?)
  end

  def test_process_file_with_stringio_object
    stringio = StringIO.new(@zone_data)
    zone = @reader.process_file(stringio)
    check_zone_data_is_valid(zone)
    assert_equal(false, stringio.closed?)
    stringio.close
  end

  # The reader reattaches a quoted tail for every type, so a parenthesis right
  # before a quote must separate it too: the parenthesis is stripped from the
  # line before the quoted text goes back on.
  PAREN_QUOTE_ZONE = <<~ZONEDATA
    $TTL 3600
    caa    IN CAA   0 issue("ca.example.net")
    hinfo  IN HINFO ("cpu" "os")
    txt    IN TXT   ("abc" "def")
  ZONEDATA

  def test_zone_parenthesis_before_quote
    reader = Dnsruby::ZoneReader.new('example.com.')
    caa, hinfo, txt = reader.process_file(StringIO.new(PAREN_QUOTE_ZONE))

    assert_equal('issue', caa.property_tag)
    assert_equal('ca.example.net', caa.property_value)

    assert_equal('cpu', hinfo.cpu)
    assert_equal('os', hinfo.os)

    assert_equal(['abc', 'def'], txt.strings)
  end

  # A backslash escaping the quote abuts it too. RFC 1035 sec 5.1 makes \" a
  # literal quote within an unquoted character-string, so each of these is one
  # string, not two.
  ESCAPED_QUOTE_ZONE = <<~'ZONEDATA'
    $TTL 3600
    lead   IN TXT   \"escaped
    mid    IN TXT   abc\"def
  ZONEDATA

  def test_zone_escaped_quote_not_separated
    reader = Dnsruby::ZoneReader.new('example.com.')
    lead, mid = reader.process_file(StringIO.new(ESCAPED_QUOTE_ZONE))

    assert_equal(['"escaped'], lead.strings)
    assert_equal(['abc"def'], mid.strings)
  end
end

