# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import std;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "127.0.0.1";
    .port = "80";
    .connect_timeout = 1s;
    .first_byte_timeout = 200s;
}


acl purge {
    "127.0.0.1";
    "localhost";
}


sub vcl_recv {
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
        return(synth(405,"Not allowed."));
        }
        # jump to hit/miss

        return (purge);
    }
    
    # Handle IPv6
    if (req.http.Host ~ "^ipv6.*") {
        set req.http.host = regsub(req.http.host, "^ipv6\.(.*)","www\.\1");
    }

    if (req.restarts == 0) {
        if (req.http.x-forwarded-for) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    # remove double // in urls,
    set req.url = regsuball( req.url, "//", "/"      );
    
    # Properly handle different encoding types
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf)$") {
            # No point in compressing these
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unkown algorithm
            unset req.http.Accept-Encoding;
        }
    }

    # Compatiblity with Apache log
    unset req.http.X-Forwarded-For;
    set req.http.X-Forwarded-For = client.ip;
    
    # Remove has_js and Google Analytics __* cookies.
    if (req.http.cookie) {
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|has_js)=[^;]*", "");
        # Remove a ";" prefix, if present.
        set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");
       
        # Remove empty cookies.
        if (req.http.Cookie ~ "^\s*$") {
            unset req.http.Cookie;
        }
    }

    set req.backend_hint = default;

    # default
    if (req.restarts == 0) {
        if (req.http.x-forwarded-for) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    # disable cookies for static files
    if (req.url ~ "\.(js|css|jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|pdf)$" && ! (req.url ~ "\.(php)") ) {
        unset req.http.Cookie;
        return (hash);
    }

    # pipe on weird http methods
    if (req.method !~ "^GET|HEAD|PUT|POST|TRACE|OPTIONS|DELETE$") {
        return(pipe);
    }

    if (req.method == "GET" && (req.url ~ "^/?mylogout=")) {
        unset req.http.Cookie;
        return (pass);
    }

    #we should not cache any page for Prestashop backend
    if (req.method == "GET" && (req.url ~ "^/admin")) {
        return (pass);
    }

    #we should not cache any custom directory
    if (req.method == "GET" && (req.url ~ "^/custom")) {
        return (pass);
    }

    #we should not cache any page for customers
    if (req.method == "GET" && (req.url ~ "^/authentification" || req.url ~ "^/mon-compte")) {
        return (pass);
    }

    #we should not cache any page for customers
    if (req.method == "GET" && (req.url ~ "^/informations" || req.url ~ "^/unt.php")) {
        return (pass);
    }

    #we should not cache any page for sales
    if (req.method == "GET" && (req.url ~ "^/commande" || req.url ~ "^/historique")) {
        return (pass);
    }

    #we should not cache any page for sales
    if (req.method == "GET" && (req.url ~ "^/adresse" || req.url ~ "^/order-detail.php")) {
        return (pass);
    }

    #we should not cache any page for sales
    if (req.method == "GET" && (req.url ~ "^/order-confirmation.php" || req.url ~ "^/order-return.php")) {
        return (pass);
    }

    #we should not cache any module
    if (req.method == "GET" && req.url ~ "^/module") {
        return (pass);
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Do not cache POST request
    if (req.method == "POST") {
        return (pipe);
    }

    # Ignore empty cookies
    if (req.http.Cookie ~ "^\s*$") {
        unset req.http.Cookie;
    }

    set req.url = regsub(req.url, "\.js\?.*", ".js");
    set req.url = regsub(req.url, "\.css\?.*", ".css");
    set req.url = regsub(req.url, "\.jpg\?.*", ".jpg");
    set req.url = regsub(req.url, "\.gif\?.*", ".gif");
    set req.url = regsub(req.url, "\.swf\?.*", ".swf");
    set req.url = regsub(req.url, "\.xml\?.*", ".xml");
    
    return (hash);
}


sub vcl_hash {
    hash_data(req.url);
    
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    
    if (req.http.Cookie) {
        hash_data(req.http.Cookie);
    }
    
    # If the client supports compression, keep that in a different cache
    if (req.http.Accept-Encoding) {
        hash_data(req.http.Accept-Encoding);
    }

    return(lookup);
}

sub vcl_pass {
    set req.http.X-marker = "pass" ;
}

sub vcl_pipe {
    # Note that only the first request to the backend will have
    # X-Forwarded-For set. If you use X-Forwarded-For and want to
    # have it set for all requests, make sure to have:
    # set bereq.http.connection = "close";
    # here. It is not set by default as it might break some broken web
    # applications, like IIS with NTLM authentication.

    #set bereq.http.Connection = "Close";
    return (pipe);
}


sub vcl_backend_response {
    # Bypass cache for files > 10 MB
    if (std.integer(beresp.http.Content-Length, 0) > 10485760) {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    if ( ! beresp.http.Content-Encoding ~ "gzip" ) {
        set beresp.do_gzip = true;
    }

    #unset beresp.http.expires;
    if (bereq.url ~ "\.(jpeg|jpg|png|gif|ico|swf|js|css|gz|rar|txt|bzip|pdf)$") {
        unset beresp.http.set-cookie;
    }

    if (beresp.ttl > 0s ) {
        if (beresp.status >= 300 && beresp.status <= 399) {
            set beresp.ttl = 10m;
        }
        if (beresp.status >= 399) {
            set beresp.ttl = 0s;
        }
    }

    if (beresp.status >= 399) {
        unset beresp.http.set-cookie;
    }

    # Maximum 24h de cache
    if (beresp.ttl > 86400s) {
        set beresp.ttl = 86400s;
    }
    
    #        if (bereq.http.X-marker == "pass" ) {
    #                unset bereq.http.X-marker;
    #                set beresp.http.X-marker = "pass";
    #                set beresp.ttl = 0s ;
    #        }

    # Only allow cookies to be set if we're in admin area
    #if (beresp.http.Set-Cookie && bereq.url !~ "^/wp-(login|admin)") {
    #      unset beresp.http.Set-Cookie;
    #}
    
    if (bereq.method == "GET" && (bereq.url ~ "^/?mylogout=")) {
        set beresp.ttl = 0s;
        unset beresp.http.Set-Cookie;
        set beresp.uncacheable = true;
        return(deliver);
    }

    # don't cache response to posted requests or those with basic auth
    if ( bereq.method == "POST" || bereq.http.Authorization ) {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    # don't cache search results
    if ( bereq.url ~ "\?s=" || bereq.url ~ "^/recherche"){
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    # only cache status ok
    if ( beresp.status != 200 ) {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    # no cache
    #if (beresp.http.X-No-Cache) {
    #    set beresp.uncacheable = true;
    #    set beresp.ttl = 120s;
    #    return (deliver);
    #}
    #set beresp.uncacheable = true;
    
    return (deliver);
}

sub vcl_deliver {
    if (obj.hits > 0){
        set resp.http.X-Varnish-Cache = "HIT";
    } else {
        set resp.http.X-Varnish-Cache = "MISS";
    }
    if (resp.http.X-marker == "pass" ) {
        unset resp.http.X-marker;
        set resp.http.X-Varnish-Cache = "PASS";
    }
    unset resp.http.Via;
    unset resp.http.X-Whatever;
    unset resp.http.X-Powered-By;
    unset resp.http.X-Varnish;
    #unset resp.http.Age;
    unset resp.http.Server;

    set resp.http.X-Frame-Options = "SAMEORIGIN";
    set resp.http.X-Xss-Protection = "1; mode=block";
}

sub vcl_synth {
    if (resp.status >= 500 && req.restarts < 4) {
        return (restart);
    }
}
