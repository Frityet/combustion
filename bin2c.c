#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

typedef struct {
    uint8_t *data;
    size_t size;
} Buffer_t;

Buffer_t bin2c(const uint8_t *data, size_t size, const char *symname, size_t symname_size)
{
    Buffer_t buffer = {
        .size = size * 4 + symname_size + sizeof("#include <stddef.h>\n\nconst unsigned char ""[] = {\n};\nconst size_t ""_size = "";\n")
                       + (symname_size * 2) + 18,
        .data = calloc(buffer.size, sizeof(uint8_t)),
    };

    if (buffer.data == NULL)
        return (Buffer_t){0};

    char *tmp = (char *)buffer.data;

    tmp += snprintf(tmp, buffer.size, "#include <stddef.h>\n\nconst unsigned char %s[] = {\n", symname);

    int t = time(NULL);
    printf("\x1b[?25l");
    for (size_t i = 0; i < size; i++) {
        tmp += snprintf(tmp, buffer.size, "0x%02x, ", data[i]);
        printf("\x1b[32mWrote \x1b[35m%zu\x1b[32m bytes \x1b[0m(\x1b[35m%.2lf%%\x1b[0m, \x1b[32mtaken\x1b[0m \x1b[35m%zus\x1b[0m)\r", i, (((double)i) / size) * 100, time(NULL) - t);
        if (i % 16 == 0)
            tmp += snprintf(tmp, buffer.size, "\n");
    }
    printf("\x1b[?25h\n");

    tmp += snprintf(tmp, buffer.size, "\n};\nconst size_t %s_size = %zu;\n", symname, size);

    buffer.size = tmp - (char *)buffer.data;

    return buffer;
}
