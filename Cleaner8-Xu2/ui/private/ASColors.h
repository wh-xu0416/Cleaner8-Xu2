#import <UIKit/UIKit.h>

static inline UIColor *ASColorRGBA(UInt32 r, UInt32 g, UInt32 b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

// #F6F6F6FF
static inline UIColor *ASBG(void) { return ASColorRGBA(0xF6,0xF6,0xF6,1); }

// #E0E0E0FF
static inline UIColor *ASTopGray(void) { return ASColorRGBA(0xE0,0xE0,0xE0,1); }

// #008DFF00 (R=0,G=0x8D,B=0xFF, alpha=0)
static inline UIColor *ASBlueTransparent(void) { return ASColorRGBA(0x00,0x8D,0xFF,0); }

// #024DFFFF
static inline UIColor *ASBlue(void) { return ASColorRGBA(0x02,0x4D,0xFF,1); }
