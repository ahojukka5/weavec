static uint32_t weave_si_rotr(uint32_t value, unsigned int count) {
    return (value >> count) | (value << (32U - count));
}

static void weave_si_sha256_transform(
    weave_si_sha256 *context,
    const unsigned char block[64]) {
    static const uint32_t constants[64] = {
        0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
        0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
        0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
        0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
        0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
        0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
        0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
        0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
        0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
        0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
        0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
        0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
        0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
        0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
        0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
        0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
    };
    uint32_t words[64];
    for (size_t index = 0; index < 16; ++index) {
        size_t offset = index * 4;
        words[index] = ((uint32_t)block[offset] << 24) |
            ((uint32_t)block[offset + 1] << 16) |
            ((uint32_t)block[offset + 2] << 8) |
            (uint32_t)block[offset + 3];
    }
    for (size_t index = 16; index < 64; ++index) {
        uint32_t left = words[index - 15];
        uint32_t right = words[index - 2];
        uint32_t s0 = weave_si_rotr(left, 7) ^ weave_si_rotr(left, 18) ^
            (left >> 3);
        uint32_t s1 = weave_si_rotr(right, 17) ^ weave_si_rotr(right, 19) ^
            (right >> 10);
        words[index] = words[index - 16] + s0 + words[index - 7] + s1;
    }
    uint32_t a = context->state[0];
    uint32_t b = context->state[1];
    uint32_t c = context->state[2];
    uint32_t d = context->state[3];
    uint32_t e = context->state[4];
    uint32_t f = context->state[5];
    uint32_t g = context->state[6];
    uint32_t h = context->state[7];
    for (size_t index = 0; index < 64; ++index) {
        uint32_t s1 = weave_si_rotr(e, 6) ^ weave_si_rotr(e, 11) ^
            weave_si_rotr(e, 25);
        uint32_t choice = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + s1 + choice + constants[index] + words[index];
        uint32_t s0 = weave_si_rotr(a, 2) ^ weave_si_rotr(a, 13) ^
            weave_si_rotr(a, 22);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + majority;
        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }
    context->state[0] += a;
    context->state[1] += b;
    context->state[2] += c;
    context->state[3] += d;
    context->state[4] += e;
    context->state[5] += f;
    context->state[6] += g;
    context->state[7] += h;
}

static void weave_si_sha256_init(weave_si_sha256 *context) {
    memset(context, 0, sizeof(*context));
    context->state[0] = 0x6a09e667U;
    context->state[1] = 0xbb67ae85U;
    context->state[2] = 0x3c6ef372U;
    context->state[3] = 0xa54ff53aU;
    context->state[4] = 0x510e527fU;
    context->state[5] = 0x9b05688cU;
    context->state[6] = 0x1f83d9abU;
    context->state[7] = 0x5be0cd19U;
}

static void weave_si_sha256_update(
    weave_si_sha256 *context,
    const void *data,
    size_t length) {
    const unsigned char *cursor = (const unsigned char *)data;
    context->bits += (uint64_t)length * 8U;
    while (length > 0) {
        size_t available = sizeof(context->block) - context->used;
        size_t take = length < available ? length : available;
        memcpy(context->block + context->used, cursor, take);
        context->used += take;
        cursor += take;
        length -= take;
        if (context->used == sizeof(context->block)) {
            weave_si_sha256_transform(context, context->block);
            context->used = 0;
        }
    }
}

static void weave_si_sha256_finish(
    weave_si_sha256 *context,
    unsigned char digest[32]) {
    context->block[context->used++] = 0x80U;
    if (context->used > 56) {
        while (context->used < sizeof(context->block)) {
            context->block[context->used++] = 0;
        }
        weave_si_sha256_transform(context, context->block);
        context->used = 0;
    }
    while (context->used < 56) {
        context->block[context->used++] = 0;
    }
    for (size_t index = 0; index < 8; ++index) {
        context->block[63 - index] =
            (unsigned char)(context->bits >> (index * 8));
    }
    weave_si_sha256_transform(context, context->block);
    for (size_t index = 0; index < 8; ++index) {
        digest[index * 4] = (unsigned char)(context->state[index] >> 24);
        digest[index * 4 + 1] =
            (unsigned char)(context->state[index] >> 16);
        digest[index * 4 + 2] =
            (unsigned char)(context->state[index] >> 8);
        digest[index * 4 + 3] = (unsigned char)context->state[index];
    }
}

static void weave_si_hex(const unsigned char digest[32], char output[65]) {
    static const char hex[] = "0123456789abcdef";
    for (size_t index = 0; index < 32; ++index) {
        output[index * 2] = hex[digest[index] >> 4];
        output[index * 2 + 1] = hex[digest[index] & 0x0fU];
    }
    output[64] = '\0';
}

static void weave_si_sha256_bytes(
    const void *data,
    size_t length,
    char output[65]) {
    weave_si_sha256 context;
    unsigned char digest[32];
    weave_si_sha256_init(&context);
    weave_si_sha256_update(&context, data, length);
    weave_si_sha256_finish(&context, digest);
    weave_si_hex(digest, output);
}

static void weave_si_buffer_init(weave_si_buffer *buffer) {
    memset(buffer, 0, sizeof(*buffer));
}

static int weave_si_buffer_reserve(
    weave_si_buffer *buffer,
    size_t extra) {
    if (buffer->failed || extra > SIZE_MAX - buffer->length - 1) {
        buffer->failed = 1;
        return 0;
    }
    size_t needed = buffer->length + extra + 1;
    if (needed <= buffer->capacity) {
        return 1;
    }
    size_t capacity = buffer->capacity == 0 ? 128 : buffer->capacity;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    char *grown = (char *)realloc(buffer->data, capacity);
    if (grown == NULL) {
        buffer->failed = 1;
        return 0;
    }
    buffer->data = grown;
    buffer->capacity = capacity;
    return 1;
}

static int weave_si_buffer_append(
    weave_si_buffer *buffer,
    const void *data,
    size_t length) {
    if (!weave_si_buffer_reserve(buffer, length)) {
        return 0;
    }
    memcpy(buffer->data + buffer->length, data, length);
    buffer->length += length;
    buffer->data[buffer->length] = '\0';
    return 1;
}

static int weave_si_buffer_cstr(
    weave_si_buffer *buffer,
    const char *value) {
    return weave_si_buffer_append(buffer, value, strlen(value));
}

static int weave_si_buffer_char(weave_si_buffer *buffer, char value) {
    return weave_si_buffer_append(buffer, &value, 1);
}

static int weave_si_buffer_json_string(
    weave_si_buffer *buffer,
    const char *value,
    size_t length) {
    static const char hex[] = "0123456789abcdef";
    if (!weave_si_buffer_char(buffer, '"')) {
        return 0;
    }
    for (size_t index = 0; index < length; ++index) {
        unsigned char ch = (unsigned char)value[index];
        if (ch == '\\' || ch == '"') {
            if (!weave_si_buffer_char(buffer, '\\') ||
                !weave_si_buffer_char(buffer, (char)ch)) {
                return 0;
            }
        } else if (ch < 0x20U) {
            char escaped[6] = {
                '\\', 'u', '0', '0', hex[ch >> 4], hex[ch & 0x0fU],
            };
            if (!weave_si_buffer_append(buffer, escaped, sizeof(escaped))) {
                return 0;
            }
        } else if (!weave_si_buffer_char(buffer, (char)ch)) {
            return 0;
        }
    }
    return weave_si_buffer_char(buffer, '"');
}
