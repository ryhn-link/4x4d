module matrix.mxc;

import std.conv;
import std.regex;
import std.range;
import std.format;

struct MXC
{
	string server, mediaId;

	this(string mxc)
	{
		auto c = matchFirst(mxc, regex("mxc:\\/\\/(?P<server>.*)\\/(?P<mediaId>.*)"));
		server = c["server"];
		mediaId = c["mediaId"];
	}

	void opAssign(string str)
	{
		MXC m = MXC(str);

		this.server = m.server;
		this.mediaId = m.mediaId;
	}

	this(string server, string mediaId)
	{
		this.server = server;
		this.mediaId = mediaId;
	}

	string toString() const
	{
		return "mxc://" ~ server ~ "/" ~ mediaId;
	}
	alias toString this;

	string getDownloadURL(string homeserver, string filename = null, bool allowRemote = true)
	{
		string url = homeserver ~ "/_matrix/media/v3/download/%s/%s".format(server, mediaId);
		if (filename)
			url ~= "/" ~ filename;
		url ~= "?allow_remote="~allowRemote.to!string;

		return url;
	}

	string getThumbnailURL(string homeserver, bool allowRemote = true, 
		int width = 640, int height = 640, MatrixResizeMethod method = MatrixResizeMethod.crop)
	{
		return homeserver ~ "/_matrix/media/v3/thumbnail/%s/%s?allow_remote=%s&width=%s&height=%s&method=%s"
			.format(server, mediaId, allowRemote.to!string, width, height, method);
	}
}

enum MatrixResizeMethod
{
	crop = "crop",
	scale = "scale"
}