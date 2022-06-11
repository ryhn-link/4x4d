module matrix.cif;
// https://spec.matrix.org/v1.2/appendices/#common-identifier-format

struct MatrixCommonIdentifier(char _sigil, bool domainOptional = false)
{
	string localpart;
	string domain;
	@property char sigil()
	{
		return _sigil;
	}

	this(string uid)
	{
		if(uid.length > 255)
			throw new Exception("Common Identifier exceeds maximum length of 255 characters");

		if (uid[0] != _sigil)
			throw new Exception("Invalid sigil, got " ~ uid[0] ~ " expected " ~ _sigil);

		import std.string;

		auto colonpos = uid.indexOf(':');

		if (colonpos == -1)
		{
			static if (!domainOptional)
			{
				throw new Exception("No domain in common identifier '" ~ uid ~ "' found");
			}
			else
			{
				localpart = uid[1 .. $];
			}
		}
		else
		{
			localpart = uid[1 .. colonpos];
			domain = uid[colonpos + 1 .. $];
		}
	}

	void opAssign(string str)
	{
		alias cifT = MatrixCommonIdentifier!(_sigil, domainOptional);
		cifT cif = cifT(str);

		this.localpart = cif.localpart;
		this.domain = cif.domain;
	}

	string toString() // @suppress(dscanner.suspicious.object_const)
	{
		static if (domainOptional)
		{
			if (domain != null && domain.length)
				return sigil ~ localpart ~ ':' ~ domain;
			else
				return sigil ~ localpart;
		}
		else
			return sigil ~ localpart ~ ':' ~ domain;
	}

	alias toString this;
}

alias UserID = MatrixCommonIdentifier!('@');
alias RoomID = MatrixCommonIdentifier!('!');
alias RoomAlias = MatrixCommonIdentifier!('#');
alias EventID = MatrixCommonIdentifier!('$', true);

enum isSomeRoomID(T) = is(T == string) || is(T == RoomID) || is(T == RoomAlias);

unittest
{
	import std.exception;

	UserID uid = "@ryhon:ryhn.link";
	enforce(uid.localpart == "ryhon");
	enforce(uid.domain == "ryhn.link");
	enforce(uid.toString == "@ryhon:ryhn.link");

	RoomID rid = "!abcd:ryhn.link";
	enforce(rid.localpart == "abcd");
	enforce(rid.domain == "ryhn.link");
	enforce(rid.toString == "!abcd:ryhn.link");

	RoomAlias ra = "#abcd:ryhn.link";
	enforce(ra.localpart == "abcd");
	enforce(ra.domain == "ryhn.link");
	enforce(ra.toString == "#abcd:ryhn.link");

	EventID ev = "$deadbeef";
	enforce(ev.localpart == "deadbeef");
	enforce(ev.domain == null);
	enforce(ev.toString == "$deadbeef");

	ev = "$a7ebadf00d:ryhn.link";
	enforce(ev.localpart == "a7ebadf00d");
	enforce(ev.domain == "ryhn.link");
	enforce(ev.toString == "$a7ebadf00d:ryhn.link");

	// Invalid sigil
	assertThrown!Exception(UserID("*ryhon:ryhn.link"));
	// No domain
	assertThrown!Exception(UserID("@ryhon"));
	// Too long
	string str;
	str.length = 256;
	assertThrown!Exception(UserID(str));
}