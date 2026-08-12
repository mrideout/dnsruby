# --
# Copyright 2007 Nominet UK
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ++

require_relative 'spec_helper'

class TestName < Minitest::Test

  include Dnsruby

  # Names on either side of the 255-octet wire limit: 249 octets of label text
  # in 5 labels, plus a length octet each and the root's zero octet, is 255.
  AT_LIMIT_NAME = "#{'a' * 63}.#{'b' * 63}.#{'c' * 63}.#{'d' * 59}.e."
  OVER_LIMIT_NAME = "#{'a' * 63}.#{'b' * 63}.#{'c' * 63}.#{'d' * 60}.e."

  def test_label_length
    Name::Label.set_max_length(Name::Label::MaxLabelLength) # Other tests may have changed this
    #  Test max label length = 63
    begin
      Name.create("a.b.12345678901234567890123456789012345678901234567890123456789012345.com")
      assert(false, "Label of more than max=63 allowed")
    rescue ResolvError
    end
  end

  def wire_length(name)
    MessageEncoder.new { |msg| msg.put_name(name, true) }.to_s.length
  end

  # Test max name length=255. The limit is on the wire form, two octets more
  # than the dotted presentation form without its trailing dot.
  def test_name_length
    assert_equal(255, wire_length(Name.create(AT_LIMIT_NAME)))

    error = assert_raises(ResolvError) { Name.create(OVER_LIMIT_NAME) }
    assert_match(/Name length is 256,/, error.message)
  end

  # An oversized name must not reach the wire through Message either, and a
  # name right at the limit must still survive the round trip.
  def test_name_length_in_message
    assert_raises(ResolvError) { Message.new(OVER_LIMIT_NAME, "A") }

    message = Message.new(AT_LIMIT_NAME, "A")
    message.add_answer(RR.create("#{AT_LIMIT_NAME} 3600 IN NS #{AT_LIMIT_NAME}"))
    decoded = Message.decode(message.encode)
    assert_equal(AT_LIMIT_NAME, decoded.question[0].qname.to_s + ".")
    assert_equal(AT_LIMIT_NAME, decoded.answer[0].domainname.to_s + ".")
  end

  def test_absolute
    n = Name.create("example.com")
    assert(!n.absolute?)
    n = Name.create("example.com.")
    assert(n.absolute?)
  end

  def test_wild
    n = Name.create("example.com")
    assert(!n.wild?)
    n = Name.create("*.example.com.")
    assert(n.wild?)
  end

  def test_canonical_ordering
    names = []
    names.push(Name.create("example"))
    names.push(Name.create("a.example"))
    names.push(Name.create("yljkjljk.a.example"))
    names.push(Name.create("Z.a.example"))
    names.push(Name.create("zABC.a.EXAMPLE"))
    names.push(Name.create("z.example"))
    names.push(Name.create("\001.z.example"))
    names.push(Name.create("*.z.example"))
#    names.push(Name.create("\200.z.example"))
    names.push(Name.create(["c8"].pack("H*")+".z.example"))
    names.each_index {|i|
      if (i < (names.length() - 1))
        assert(names[i].canonically_before(names[i+1]))
        assert(!(names[i+1].canonically_before(names[i])))
      end
    }
    assert(Name.create("x.w.example").canonically_before(Name.create("z.w.example")))
    assert(Name.create("x.w.example").canonically_before(Name.create("a.z.w.example")))
  end

  def test_escapes
    n1 = Name.create("\\nall.all.")
    n2 = Name.create("nall.all.")
    assert(n1 == n2, n1.to_s)
  end

  def test_punycode
    [
      [
        "møllerriis.com",
        "xn--mllerriis-l8a.com"
      ],
      [
        "フガフガ。hogehoge.エグザンプル.JP",
        "xn--mcka5jb.hogehoge.xn--ickqs6k2dyb.jp"
      ],
      [
        "フガ#フガ。hogehoge.エグザンプル.JP",
        "xn--#-yeub5nc.hogehoge.xn--ickqs6k2dyb.jp"
      ]
    ].each do |tc|
      assert_equal(Dnsruby::Name.create(tc[0]).to_s, tc[1])
    end
  end
end
