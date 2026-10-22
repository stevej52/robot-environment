"""Application cloud authority: exact caller permits, bounded payloads, no model grants.

This protects the model-to-cloud boundary, not a compromised jeston account or
unauthenticated upstream DDS audio. A new brain epoch invalidates prior permits.
"""
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import stat
import time
import unicodedata

POLICY_PATH = Path('/etc/rosie-cloud/policy.json')
KEY_PATH = Path('/etc/rosie-cloud/caller.key')
DESTINATION = 'https://api.anthropic.com'
CALLER = 'rosie-listen-completed-audio'
SYSTEM = ('You are Rosie, a friendly household robot. Answer the current question clearly '
          'in at most four short spoken sentences. You receive only cloud-authorized '
          'conversation text. You have no access to private memory, files, tools, '
          'robot controls, or permission settings.')
DEFAULT_POLICY = {'version': 1, 'ordinary_audio': 'automatic', 'destination': DESTINATION,
                  'max_text_chars': 4096, 'max_history_chars': 12000, 'max_history_turns': 6,
                  'permit_seconds': 120, 'max_tokens_quick': 2000, 'max_tokens_think': 12000,
                  'allow_model_difficulty_handoff': True}
ASK_FIELDS = frozenset(('text', 'lead_in', 'think', 'terse', 'speaker', 'fun', 'hold',
                        'health', 'then_say', 'cloud_permit', 'local_only'))


def is_local_only(text):
    """Conservative deny-only syntax, not a semantic privacy classifier.

    After optional 'hey/ok/okay Rosie', prefixes 'private', 'local only', and
    'keep this local/private' deny cloud. Anywhere, exact 'local only', 'keep this local/private',
    'no cloud', or don't/do not/never send/share/upload/forward ... cloud/Claude/
    Anthropic (within 100 chars), or don't/do not/never use/call/ask Claude/cloud,
    also deny. Quoted directives may deliberately over-deny.
    """
    if not isinstance(text, str):
        return True
    # Normalization is deny-only; permits still bind the original exact text bytes.
    syntax = unicodedata.normalize('NFKC', text).translate(str.maketrans({
        '\u2018': "'", '\u2019': "'", '\u02bc': "'", '-': ' ', '\u2010': ' ',
        '\u2011': ' ', '\u2012': ' ', '\u2013': ' ', '\u2014': ' ', '\u2212': ' '}))
    syntax = re.sub(r'\s+', ' ', syntax)
    normalized = re.sub(r"^\s*(?:(?:hey|ok|okay)[\s,:;!?]+)?rosie\b[\s,:;!?.]*", '', syntax, flags=re.I)
    if re.match(r'^\s*(?:private|local only|keep this (?:local|private))\b', normalized, re.I):
        return True
    patterns = (r'\b(?:local only|keep this local|keep this private|no cloud)\b',
                r"\b(?:do not|don't|dont|never)\s+(?:send|share|upload|forward)\b.{0,100}\b(?:cloud|claude|anthropic)\b",
                r"\b(?:do not|don't|dont|never)\s+(?:use|call|ask)\s+(?:the\s+)?(?:cloud|claude|anthropic)\b")
    return any(re.search(pattern, syntax, re.I | re.S) for pattern in patterns)


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def restrict_provider_request(request):
    """httpx2 request hook: no proxy, redirect, or model-selected provider route."""
    url = request.url
    if (url.scheme != 'https' or url.host != 'api.anthropic.com' or url.port not in (None, 443)
            or url.path != '/v1/messages' or url.query):
        raise PermissionError('Unapproved cloud destination')


def protected_read(path, limit):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise PermissionError('Absolute protected path required')
    for parent in reversed((path,) + tuple(path.parents)):
        info = parent.lstat()
        if stat.S_ISLNK(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise PermissionError('Unprotected cloud policy path')
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
        raise PermissionError('Invalid cloud policy file')
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
            raise PermissionError('Cloud policy file changed during open')
        data = os.read(fd, limit + 1)
        if len(data) > limit:
            raise PermissionError('Cloud policy file too large')
        return data
    finally:
        os.close(fd)


class Authority:
    def __init__(self, reader=protected_read, clock=time.time):
        self.reader, self.clock = reader, clock

    def policy(self):
        value = json.loads(self.reader(POLICY_PATH, 8192))
        if set(value) != set(DEFAULT_POLICY):
            raise PermissionError('Invalid cloud policy fields')
        if value['ordinary_audio'] not in ('automatic', 'local_only'):
            raise PermissionError('Invalid cloud channel mode')
        for name in DEFAULT_POLICY:
            if name != 'ordinary_audio' and value[name] != DEFAULT_POLICY[name]:
                raise PermissionError('Unsupported cloud policy setting')
        return value

    def enabled(self):
        try:
            return self.policy()['ordinary_audio'] == 'automatic'
        except Exception:
            return False

    def key(self):
        key = self.reader(KEY_PATH, 256).strip()
        if not re.fullmatch(rb'[A-Za-z0-9_-]{40,128}', key):
            raise PermissionError('Invalid caller key')
        return key

    def issue(self, text, epoch, think=False):
        policy = self.policy()
        if policy['ordinary_audio'] != 'automatic' or not isinstance(text, str) or not text.strip() or is_local_only(text):
            raise PermissionError('Cloud channel is not authorized')
        if len(text) > policy['max_text_chars'] or not re.fullmatch(r'[a-f0-9]{32}', epoch or '') or type(think) is not bool:
            raise PermissionError('Invalid text length or brain epoch')
        now = int(self.clock())
        permit = {'version': 1, 'caller': CALLER, 'epoch': epoch,
                  'nonce': secrets.token_hex(16), 'issued': now,
                  'expires': now + policy['permit_seconds'], 'destination': DESTINATION,
                  'requested_think': think,
                  'policy_sha256': hashlib.sha256(canonical(policy)).hexdigest(),
                  'text_sha256': hashlib.sha256(text.encode('utf-8')).hexdigest()}
        permit['mac'] = hmac.new(self.key(), canonical(permit), hashlib.sha256).hexdigest()
        return permit


class CloudBoundary:
    def __init__(self, authority=None):
        self.authority = authority or Authority()
        self.epoch = secrets.token_hex(16)
        self.used = set()
        self.history = []
        self.current = None
        self._inflight = False

    def clear(self):
        self.current = None
        self.history.clear()
        self._inflight = False

    def begin(self, ask):
        self.current = None
        self._inflight = False
        try:
            # 2026-10-21: a held ask (Rosie thinking ahead) may carry a permit too; the brain sends
            # nothing to the cloud before listen's go, and the permit still binds the exact words.
            if (not isinstance(ask, dict) or set(ask) - ASK_FIELDS or 'health' in ask or 'then_say' in ask
                    or ask.get('local_only', False) is not False):
                raise PermissionError('This channel is local-only')
            text = ask.get('text')
            permit = ask.get('cloud_permit')
            self.validate(text, permit)
            if ask.get('think', False) is not permit['requested_think']:
                raise PermissionError('Caller thinking mode changed')
            # Copy only the actual permitted text; no caller metadata enters cloud context.
            self.current = {'text': text, 'permit': dict(permit)}
            return True
        except Exception:
            self.clear()
            return False

    def validate(self, text, permit):
        policy = self.authority.policy()
        if policy['ordinary_audio'] != 'automatic' or not isinstance(text, str) or not text.strip() or len(text) > policy['max_text_chars'] or is_local_only(text):
            raise PermissionError('Cloud channel is local-only')
        fields = {'version', 'caller', 'epoch', 'nonce', 'issued', 'expires', 'destination',
                  'policy_sha256', 'text_sha256', 'requested_think', 'mac'}
        if not isinstance(permit, dict) or set(permit) != fields:
            raise PermissionError('Missing or invalid caller permit')
        if (permit['version'] != 1 or permit['caller'] != CALLER or permit['epoch'] != self.epoch
                or permit['destination'] != DESTINATION or not isinstance(permit['nonce'], str)
                or not re.fullmatch(r'[a-f0-9]{32}', permit['nonce'])
                or type(permit['requested_think']) is not bool
                or type(permit['issued']) is not int or type(permit['expires']) is not int):
            raise PermissionError('Caller permit authority mismatch')
        now = self.authority.clock()
        if not permit['issued'] <= now <= permit['expires'] or permit['expires']-permit['issued'] != policy['permit_seconds']:
            raise PermissionError('Expired or future caller permit')
        if permit['nonce'] in self.used:
            raise PermissionError('Caller permit already consumed')
        if permit['text_sha256'] != hashlib.sha256(text.encode('utf-8')).hexdigest():
            raise PermissionError('Caller text changed')
        if permit['policy_sha256'] != hashlib.sha256(canonical(policy)).hexdigest():
            raise PermissionError('Caller policy changed')
        body = {key: value for key, value in permit.items() if key != 'mac'}
        expected = hmac.new(self.authority.key(), canonical(body), hashlib.sha256).hexdigest()
        if not isinstance(permit['mac'], str) or not hmac.compare_digest(expected, permit['mac']):
            raise PermissionError('Caller permit signature failed')
        return policy

    def allowed(self):
        try:
            if self.current is None or self._inflight:
                return False
            self.validate(self.current['text'], self.current['permit'])
            return True
        except Exception:
            self.clear()
            return False

    def take_payload(self):
        if self.current is None or self._inflight:
            raise PermissionError('No unused authorized cloud request')
        policy = self.validate(self.current['text'], self.current['permit'])
        if len(self.used) >= 10000:
            raise PermissionError('Permit cache full; restart invalidates outstanding permits')
        # Brain has one answer worker. Consume before the first SDK call, including failures.
        self.used.add(self.current['permit']['nonce'])
        self._inflight = True
        history = list(self.history[-policy['max_history_turns']*2:])
        while history and sum(len(item['content']) for item in history) + len(self.current['text']) > policy['max_history_chars']:
            history = history[2:]
        return SYSTEM, history + [{'role': 'user', 'content': self.current['text']}]

    def record_cloud_reply(self, text):
        if not self._inflight or self.current is None or not isinstance(text, str):
            raise PermissionError('No authorized cloud reply')
        policy = self.authority.policy()
        if policy['ordinary_audio'] != 'automatic' or len(text) > policy['max_history_chars']:
            self.clear()
            return
        self.history.extend(({'role': 'user', 'content': self.current['text']},
                             {'role': 'assistant', 'content': text}))
        self.history = self.history[-policy['max_history_turns']*2:]
        while self.history and sum(len(item['content']) for item in self.history) > policy['max_history_chars']:
            self.history = self.history[2:]
        self.current = None
        self._inflight = False
