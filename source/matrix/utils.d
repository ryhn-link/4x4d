module matrix.utils;

import requests;

class RequestBuilder
{
	string url;
	string[string] params;
	string[string] headers;

	this(string url)
	{
		this.url = url;
	}


	RequestBuilder setParameter(string key, string value)
	{
		if(value)
			params[key] = value;
		return this;
	}

	RequestBuilder setParameter(T)(string key, T value)
	{
		import std.conv : to;
		return setParameter(key, value.to!string);
	}

	RequestBuilder setHeader(string name, string value)
	{
		headers[name] = value;
		return this;
	}

	Response get()
	{
		Request r = Request(); r.sslSetVerifyPeer(false);
		return r.get(url, params);
	}

	Response put()
	{
		Request r = Request(); r.sslSetVerifyPeer(false);
		import requests.utils : aa2params;
		return r.put(url, params.aa2params);
	}

	Response put(T)(T data, string contentType)
	{
		import std.stdio;
		Request r = Request(); r.sslSetVerifyPeer(false);
		return r.put(url, data, contentType);
	}

	Response post()
	{
		Request r = Request(); r.sslSetVerifyPeer(false);
		return r.post(url, params);
	}

	Response post(T)(T data, string contentType)
	{
		import std.stdio;
		Request r = Request(); r.sslSetVerifyPeer(false);
		return r.post(url, data, contentType);
	}
}

import matrix : MatrixClient;
RequestBuilder addAuth(RequestBuilder rb, MatrixClient c)
{
	import std.exception : enforce;
	enforce(c.accessToken, "Atempted to call authenticated method without access token");
	rb.setHeader("Authorization", "Bearer " ~ c.accessToken);
	rb.setParameter("access_token", c.accessToken);
	return rb;
}

import std.json;

JSONValue mxParseResponse(Response r)
{
	JSONValue json = parseJSON(r.responseBody.toString);
	if((r.code <= 200 && r.code >= 300) || "errcode" in json)
	{
		import matrix : MatrixException;
		throw new MatrixException(r.code, json);
	}

	return json;
}

JSONValue mxGet(RequestBuilder rb)
{
	auto resp = rb.get();
	return mxParseResponse(resp);
}

JSONValue mxPost(RequestBuilder rb)
{
	auto resp = rb.post();
	return mxParseResponse(resp);
}

JSONValue mxPost(RequestBuilder rb, JSONValue json)
{
	return mxPost(rb, json.toString, "application/json");
}

JSONValue mxPost(T)(RequestBuilder rb, T data, string contentType)
{
	auto resp = rb.post(data, contentType);
	return mxParseResponse(resp);
}

JSONValue mxPut(RequestBuilder rb)
{
	auto resp = rb.post();
	return mxParseResponse(resp);
}

JSONValue mxPut(RequestBuilder rb, JSONValue json)
{
	return mxPut(rb, json.toString, "application/json");
}

JSONValue mxPut(T)(RequestBuilder rb, T data, string contentType)
{
	auto resp = rb.put(data, contentType);
	return mxParseResponse(resp);
}