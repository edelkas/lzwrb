#include <stdio.h>
#include <stdlib.h>
#include "gifenc.h"

int main(int argc, char* argv[]) {
    if (argc != 3) {
        printf("You need to supply the width and height as arguments.\n");
        exit(1);
    }

    int i, j;
    int w = atoi(argv[1]), h = atoi(argv[2]);

    FILE *fp = fopen("pixels", "rb");
    if (fp == NULL) {
        printf("Pixel file not found.\n");
        exit(1);
    }
    uint8_t pixels[w * h];
    int pcount = fread(pixels, 1, w * h, fp);
    if (pcount != w * h) {
        printf("Incorrect pixel file length.\n");
        exit(1);
    }
    fclose(fp);

    uint8_t palette[3 * 256];
    for (i = 0; i < 256; i++) {
        palette[3 * i + 0] = i;
        palette[3 * i + 1] = i;
        palette[3 * i + 2] = i;
    }

    /* create a GIF */
    ge_GIF *gif = ge_new_gif(
        "example.gif",  /* file name */
        w, h,           /* canvas size */
        palette,
        8,              /* palette depth == log2(# of colors) */
        -1,             /* no transparency */
        0               /* infinite loop */
    );
    /* draw some frames */
    for (j = 0; j < w * h; j++) gif->frame[j] = pixels[j];
    ge_add_frame(gif, 0);
    /* remember to close the GIF */
    ge_close_gif(gif);
    return 0;
}
