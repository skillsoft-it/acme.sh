#!/bin/bash

#
# ULTRA_USR="your_user_goes_here"
#
# ULTRA_PWD="some_password_goes_here"

ULTRA_API="https://api.ultradns.com/v3/"
ULTRA_AUTH_API="https://api.ultradns.com/v2/"

#Usage: add _acme-challenge.www.domain.com "some_long_string_of_characters_go_here_from_lets_encrypt"
dns_ultra_add() {
  fulldomain=$1
  txtvalue=$2
  export txtvalue
  ULTRA_USR="${ULTRA_USR:-$(_readaccountconf_mutable ULTRA_USR)}"
  ULTRA_PWD="${ULTRA_PWD:-$(_readaccountconf_mutable ULTRA_PWD)}"
  if [ -z "$ULTRA_USR" ] || [ -z "$ULTRA_PWD" ]; then
    ULTRA_USR=""
    ULTRA_PWD=""
    _err "You didn't specify an UltraDNS username and password yet"
    return 1
  fi
  # save the username and password to the account conf file.
  _saveaccountconf_mutable ULTRA_USR "$ULTRA_USR"
  _saveaccountconf_mutable ULTRA_PWD "$ULTRA_PWD"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _zone "${_zone}"
  _debug _record "${_record}"
  
  _debug "Getting txt records"
  _ultra_rest GET "zones/${_zone}./rrsets/TXT/${_record}"
  if printf "%s" "$response" | grep \"totalCount\" >/dev/null; then
    _err "Error, it would appear that this record already exists. Please review existing TXT records for this domain."
    return 1
  fi

  _info "Adding record"
  if _ultra_rest POST "zones/${_zone}./rrsets/TXT/${_record}" '{"ttl":300,"rdata":["'"${txtvalue}"'"]}'; then
    if _contains "$response" "Successful"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "Resource Record of type 16 with these attributes already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."

}

dns_ultra_rm() {
  fulldomain=$1
  txtvalue=$2
  export txtvalue
  ULTRA_USR="${ULTRA_USR:-$(_readaccountconf_mutable ULTRA_USR)}"
  ULTRA_PWD="${ULTRA_PWD:-$(_readaccountconf_mutable ULTRA_PWD)}"
  if [ -z "$ULTRA_USR" ] || [ -z "$ULTRA_PWD" ]; then
    ULTRA_USR=""
    ULTRA_PWD=""
    _err "You didn't specify an UltraDNS username and password yet"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _zone "${_zone}"
  _debug _record "${_record}"

  _debug "Getting TXT records"
  _ultra_rest GET "zones/${_zone}./rrsets/TXT/${_record}"

  if ! printf "%s" "$response" | grep \"resultInfo\" >/dev/null; then
    _err "There was an error in obtaining the resource records for ${_zone}"
    return 1
  fi

  count=$(echo "$response" | _egrep_o "\"returnedCount\":[^,]*" | cut -d: -f2 | cut -d'}' -f1)
  _debug count "${count}"
  if [ "${count}" = "" ]; then
    _info "Text record is not present, will not delete anything."
  else
    if ! _ultra_rest DELETE "zones/${_zone}./rrsets/TXT/${_record}" '{"ttl":300,"rdata":["'"${txtvalue}"'"]}'; then
      _err "Deleting the record did not succeed, please verify/check."
      return 1
    fi
    _contains "$response" ""
  fi

}

_get_root() {
  domain=$1
  _zone=$(printf "%s" "$domain" | rev | cut -d . -f 1-2 | rev)
  _record=${domain%".$_zone"}
  return 0
}

_ultra_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"
  if [ -z "$AUTH_TOKEN" ]; then
    _ultra_login
  fi
  _debug TOKEN "$AUTH_TOKEN"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $AUTH_TOKEN"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$ULTRA_API$ep" "" "$m")"
  else
    response="$(_get "$ULTRA_API$ep")"
  fi
}

_ultra_login() {
  export _H1=""
  export _H2=""
  AUTH_TOKEN=$(_post "grant_type=password&username=${ULTRA_USR}&password=${ULTRA_PWD}" "${ULTRA_AUTH_API}authorization/token" | cut -d, -f3 | cut -d\" -f4)
  export AUTH_TOKEN
}
