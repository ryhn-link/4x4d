module matrix.text;

// Utility functions for seding text messages (and file messages)

import matrix;
import std.json;

/// Sends a m.room.message with format of org.matrix.custom.html
/// fallback is the plain text version of html if the client doesn't support html
void sendHTML(T)(MatrixClient c, T room, string html, string fallback = null, string msgtype = "m.notice")
		if (isSomeRoomID!T)
{
	if (!fallback)
		fallback = html;
	JSONValue json = JSONValue();
	json["msgtype"] = msgtype;
	json["format"] = "org.matrix.custom.html";
	json["formatted_body"] = html;
	json["body"] = fallback;

	return c.sendEvent(room, "m.room.message", json);
}

/// Sends a m.room.message
void sendString(T)(MatrixClient c, T room, string text, string msgtype = "m.notice")
		if (isSomeRoomID!T)
{
	JSONValue json = JSONValue();
	json["msgtype"] = msgtype;
	json["body"] = text;

	return c.sendEvent(room, "m.room.message", json);
}

/// Sends a m.room.message with specified msgtype and MXC URI
void sendFile(T)(T room, string filename, MXC mxc, string msgtype = "m.file")
		if (isSomeRoomID!T)
{
	JSONValue json = JSONValue();
	json["msgtype"] = msgtype;
	json["url"] = mxc.toString;
	json["body"] = filename;

	return c.sendEvent(room, "m.room.message", json);
}

/// Sends a m.room.message with type of m.image with specified MXC URI
void sendImage(T)(MatrixClient c, T room, string filename, MXC mxc)
		if (isSomeRoomID!T)
{
	return c.sendFile(room, "m.image", filename, mxc);
}

void addReaction(T)(MatrixClient c, T room, EventID event, string emoji)
		if (isSomeRoomID!T)
{
	JSONValue json = JSONValue();
	req["m.relates_to"] = JSONValue();
	req["m.relates_to"]["rel_type"] = "m.annotation";
	req["m.relates_to"]["event_id"] = event.toString;
	req["m.relates_to"]["key"] = emoji;

	return c.sendEvent(room, "m.reaction", json);
}
