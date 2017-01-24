//
//  IJSVGExporter.m
//  IJSVGExample
//
//  Created by Curtis Hard on 06/01/2017.
//  Copyright © 2017 Curtis Hard. All rights reserved.
//

#import "IJSVGExporter.h"
#import "IJSVG.h"
#import "IJSVGGradientLayer.h"
#import "IJSVGRadialGradient.h"
#import "IJSVGLinearGradient.h"
#import "IJSVGPatternLayer.h"
#import "IJSVGImageLayer.h"
#import "IJSVGShapeLayer.h"
#import "IJSVGGroupLayer.h"
#import "IJSVGStrokeLayer.h"
#import "IJSVGMath.h"
#import "IJSVGExporterPathInstruction.h"

@implementation IJSVGExporter

#define XML_DOC_VERSION 1.1f
#define XML_DOC_NS @"http://www.w3.org/2000/svg"
#define XML_DOC_NSXLINK @"http://www.w3.org/1999/xlink"
#define XML_DOCTYPE_VERSION @"1.0"
#define XML_DOC_CHARSET @"UTF-8"
#define XML_DOC_GENERATOR @"Generated by IJSVG (https://github.com/curthard89/IJSVG)"

@synthesize title;
@synthesize description;

const NSArray * IJSVGInheritableAttributes()
{
    static NSArray * _attributes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _attributes = [@[
            @"clip-rule",
            @"color",
            @"color-interpolation",
            @"color-interpolation-filters",
            @"color-profile",
            @"color-rendering",
            @"cursor",
            @"direction",
            @"fill",
            @"fill-opacity",
            @"fill-rule",
            @"font",
            @"font-family",
            @"font-size",
            @"font-size-adjust",
            @"font-stretch",
            @"font-style",
            @"font-variant",
            @"font-weight",
            @"glyph-orientation-horizontal",
            @"glyph-orientation-vertical",
            @"image-rendering",
            @"kerning",
            @"letter-spacing",
            @"marker",
            @"marker-end",
            @"marker-mid",
            @"marker-start",
            @"pointer-events",
            @"shape-rendering",
            @"stroke",
            @"stroke-dasharray",
            @"stroke-dashoffset",
            @"stroke-linecap",
            @"stroke-linejoin",
            @"stroke-miterlimit",
            @"stroke-opacity",
            @"stroke-width",
            @"text-anchor",
            @"text-rendering",
            @"visibility",
            @"white-space",
            @"word-spacing",
            @"writing-mode"] retain];
    });
    return _attributes;
}

void IJSVGApplyAttributesToElement(NSDictionary *attributes, NSXMLElement *element) {
    [element setAttributesAsDictionary:attributes];
};

NSDictionary * IJSVGElementAttributeDictionary(NSXMLElement * element) {
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    for(NSXMLNode * attribute in element.attributes) {
        dict[attribute.name] = attribute.stringValue;
    }
    return dict;
};

NSString * IJSVGShortFloatString(CGFloat f)
{
    return [NSString stringWithFormat:@"%g",f];
};

NSString * IJSVGHashURL(NSString * key) {
    return [NSString stringWithFormat:@"url(#%@)",key];
};

NSString * IJSVGHash(NSString * key) {
    return [@"#" stringByAppendingString:key];
}

- (void)dealloc
{
    [_svg release], _svg = nil;
    [_dom release], _dom = nil;
    [title release], title = nil;
    [description release], description = nil;
    [super dealloc];
}

- (id)initWithSVG:(IJSVG *)svg
          options:(IJSVGExporterOptions)options
{
    if((self = [super init]) != nil) {
        _options = options;
        _svg = [svg retain];
        
        // clear memory as soon as possible
        @autoreleasepool {
            [self _prepare];
        }
    }
    return self;
}

- (NSXMLElement *)defElement
{
    if(_defElement != nil) {
        return _defElement;
    }
    return _defElement = [[NSXMLElement alloc] initWithName:@"defs"];
}

- (NSXMLElement *)rootNode
{
    // generates the root document
    NSXMLElement * root = [[[NSXMLElement alloc] initWithName:@"svg"] autorelease];
    
    // sort out viewbox
    NSRect viewBox = _svg.viewBox;
    NSDictionary * attributes = @{
        @"viewBox":[NSString stringWithFormat:@"%g %g %g %g",
                    viewBox.origin.x, viewBox.origin.y,
                    viewBox.size.width, viewBox.size.height],
        @"version": [NSString stringWithFormat:@"%g",XML_DOC_VERSION],
        @"xmlns": XML_DOC_NS,
        @"xmlns:xlink": XML_DOC_NSXLINK
    };
    
    // apply the attributes
    IJSVGApplyAttributesToElement(attributes, root);
    return root;
}

- (void)_prepare
{
    // create the stand alone DOM
    _dom = [[NSXMLDocument alloc] initWithRootElement:[self rootNode]];
    _dom.version = XML_DOCTYPE_VERSION;
    _dom.characterEncoding = XML_DOC_CHARSET;
    
    // add generator
    NSXMLNode * generatorNode = [[[NSXMLNode alloc] initWithKind:NSXMLCommentKind] autorelease];
    generatorNode.stringValue = XML_DOC_GENERATOR;
    [_dom.rootElement addChild:generatorNode];
    
    // add defs in
    [_dom.rootElement addChild:[self defElement]];
    
    // sort out header
    
    // sort out stuff, so here we go...
    [self _recursiveParseFromLayer:_svg.layer
                       intoElement:_dom.rootElement];
    
    // cleanup
    [self _cleanup];
}

- (void)_cleanup
{
    
    // convert any duplicate paths into use
    if((_options & IJSVGExporterOptionCreateUseForPaths) != 0) {
        [self _convertUseElements];
    }
    
    // cleanup def
    if((_options & IJSVGExporterOptionRemoveUselessDef) != 0) {
        [self _cleanDef];
    }
    
    // move any possible attributes to its parent group
    if((_options & IJSVGExporterOptionMoveAttributesToGroup) != 0) {
        [self _moveAttributesToGroup];
    }
    
    // collapse groups
    if((_options & IJSVGExporterOptionCollapseGroups) != 0) {
        [self _collapseGroups];
    }
    
    // clean any blank groups
    if((_options & IJSVGExporterOptionRemoveUselessGroups) != 0) {
        [self _cleanEmptyGroups];
    }
    
    // sort attributes
    if((_options & IJSVGExporterOptionSortAttributes) != 0) {
        [self _sortAttributesOnElement:_dom.rootElement];
    }
    
    // compress groups together
    if((_options & IJSVGExporterOptionCollapseGroups) != 0) {
        [self _compressGroups];
    }
}

- (void)_sortAttributesOnElement:(NSXMLElement *)element
{
    // only apply to XML elements, not XMLNodes
    if([element isKindOfClass:[NSXMLElement class]] == NO) {
        return;
    }
    [self sortAttributesOnElement:element];
    for(NSXMLElement * child in element.children) {
        [self _sortAttributesOnElement:child];
    }
}

- (void)_moveAttributesToGroup
{
    @autoreleasepool {
        
        NSArray<NSXMLElement *> * groups = [_dom nodesForXPath:@"//g"
                                                         error:nil];
        
        const NSArray * inheritableAttributes = IJSVGInheritableAttributes();
        
        for(NSXMLElement * group in groups) {
            @autoreleasepool {
                NSDictionary * intersection = @{};
                
                // does it have a mask/clip?
                BOOL hasClip = [group attributeForName:@"clip-path"] != nil ||
                    [group attributeForName:@"mask"] != nil;
                
                NSMutableArray * intersected = [[[NSMutableArray alloc] init] autorelease];
                
                // loop around each child
                for(NSXMLElement * child in group.children) {
                    if(child.attributes.count == 0) {
                        continue;
                    }
                    
                    // straight add on
                    NSDictionary * atts = [self intersectableAttributes:IJSVGElementAttributeDictionary(child)
                                                  inheritableAttributes:inheritableAttributes];
                    if(intersection.count == 0) {
                        intersection = atts;
                    } else {
                        
                        // work out the intersection
                        NSDictionary * dict = nil;
                        dict = [self intersectionInheritableAttributes:intersection
                                                     currentAttributes:atts
                                                 inheritableAttributes:inheritableAttributes];
                        
                        // break if nothing
                        if(dict == nil) {
                            continue;
                        }
                        
                        // add them
                        intersection = dict;
                    }
                    // add the child to array
                    [intersected addObject:child];
                }
                
                if(intersected.count != 0 && hasClip == NO) {
                    for(NSXMLElement * child in intersected) {
                        for(NSString * attributeName in intersection.allKeys) {
                            // remove attribute
                            [child removeAttributeForName:attributeName];
                            // add the
                            NSDictionary * atts = nil;
                            atts = @{attributeName:intersection[attributeName]};
                            IJSVGApplyAttributesToElement(atts, group);
                        }
                    }
                }
            }
        }
    }
}

- (NSDictionary *)intersectableAttributes:(NSDictionary *)atts
                    inheritableAttributes:(const NSArray *)inheritable
{
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    for(NSString * key in atts.allKeys) {
        if([inheritable containsObject:key]) {
            dict[key] = atts[key];
        }
    }
    return dict;
}

- (NSDictionary *)intersectionInheritableAttributes:(NSDictionary *)newAttributes
                                  currentAttributes:(NSDictionary *)currentAttributes
                              inheritableAttributes:(const NSArray *)inheritableAtts
{
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    for(NSString * key in newAttributes.allKeys) {
        // make sure they are the same and
        // they are inheritable
        if([currentAttributes objectForKey:key] != nil &&
           [inheritableAtts containsObject:key] &&
           [newAttributes[key] isEqualToString:currentAttributes[key]]) {
            dict[key] = currentAttributes[key];
        }
    }
    
    // nothing to return, kill it
    if(dict.count == 0) {
        return nil;
    }
    return dict;
}

- (void)_cleanDef
{
    NSXMLElement * defNode = [self defElement];
    if(defNode.children == 0) {
        NSXMLElement * parent = (NSXMLElement *)defNode.parent;
        [parent removeChildAtIndex:defNode.index];
    }
}

- (void)_cleanEmptyGroups
{
    @autoreleasepool {
        // cleanup any groups that are completely useless
        NSArray * groups = [_dom nodesForXPath:@"//g" error:nil];
        for(NSXMLElement * element in groups) {
            NSXMLElement * parent = (NSXMLElement *)element.parent;
            if(element.childCount == 0) {
                // empty group
                [(NSXMLElement *)element.parent removeChildAtIndex:element.index];
            } else if(element.attributes.count == 0) {
                // no useful data on the group
                NSInteger index = element.index;
                for(NSXMLElement * child in element.children) {
                    [(NSXMLElement *)child.parent removeChildAtIndex:child.index];
                    [parent insertChild:child
                                atIndex:index++];
                }
                [parent removeChildAtIndex:element.index];
            }
        }
    }
}

- (void)_compressGroups
{
    NSArray * groups = [_dom nodesForXPath:@"//g" error:nil];
    for(NSXMLElement * group in groups) {
        
        // whats the next group?
        if(group.parent == nil) {
            continue;
        }
        
        // compare each group with its next sibling
        NSXMLElement * nextGroup = (NSXMLElement *)group.nextSibling;
        while([self compareElement:group withElement:nextGroup]) {
            // move each child into the older group
            for(NSXMLElement * child in nextGroup.children) {
                [nextGroup removeChildAtIndex:child.index];
                [group addChild:child];
            }
            
            // remove the newer
            NSXMLElement * n = nextGroup;
            nextGroup = (NSXMLElement *)nextGroup.nextSibling;
            [(NSXMLElement *)n.parent removeChildAtIndex:n.index];
        }
    }

}

- (void)_collapseGroups
{
    NSArray * groups = [_dom nodesForXPath:@"//g" error:nil];
    const NSArray * inheritable = IJSVGInheritableAttributes();
    for(NSXMLElement * group in groups) {
    
        // dont do anything due to it being referenced
        if([group attributeForName:@"id"] != nil) {
            continue;
        }
        
        if(group.attributes.count != 0 && group.children.count == 1) {
            
            // grab the first child as its a loner
            NSXMLElement * child = (NSXMLElement *)group.children[0];
            
           for(NSXMLNode * gAttribute in group.attributes) {
               
               // if it just doesnt have the attriute, just add it
               if([child attributeForName:gAttribute.name] == NO) {
                   // remove first, or throws a wobbly
                   [group removeAttributeForName:gAttribute.name];
                   [child addAttribute:gAttribute];
                   
               } else if([gAttribute.name isEqualToString:@"transform"]) {
                   
                   // transform requires concatination
                   NSXMLNode * childTransform = [child attributeForName:@"transform"];
                   childTransform.stringValue = [NSString stringWithFormat:@"%@ %@",
                                                 gAttribute.stringValue, childTransform.stringValue];
                   
               } else if([inheritable containsObject:gAttribute.name] == NO) {
                   
                   // if its not inheritable, only remove it if its not equal
                   NSXMLNode * aAtt = [child attributeForName:gAttribute.name];
                   if(aAtt == nil || (aAtt != nil && [aAtt.stringValue isEqualToString:gAttribute.stringValue] == NO)) {
                       continue;
                   }
               }
               [group removeAttributeForName:gAttribute.name];
           }
        }
    }
}

- (BOOL)compareElement:(NSXMLElement *)element
           withElement:(NSXMLElement *)anotherElement
{
    // not a matching element
    if([element.name isEqualToString:anotherElement.name] == NO ||
       element.attributes.count != anotherElement.attributes.count) {
        return NO;
    }
    
    // compare attributes
    for(NSXMLNode * attribute in element.attributes) {
        NSString * compareString = [anotherElement attributeForName:attribute.name].stringValue;
        if([attribute.stringValue isEqualToString:compareString] == NO) {
            return NO;
        }
    }
    return YES;
}

- (void)_convertUseElements
{
    @autoreleasepool {
        NSArray * paths = [_dom nodesForXPath:@"//path"
                                        error:nil];
        
        NSCountedSet * set = [[[NSCountedSet alloc] init] autorelease];
        for(NSXMLElement * element in paths) {
            [set addObject:[element attributeForName:@"d"].stringValue];
        }
        
        NSMutableDictionary * defs = [[[NSMutableDictionary alloc] init] autorelease];
        
        // now actually compute them
        for(NSXMLElement * element in paths) {
            NSString * data = [element attributeForName:@"d"].stringValue;
            if([set countForObject:data] == 1) {
                continue;
            }
            
            // at this point, we know the path is being used more then once
            NSXMLElement * defParentElement = nil;
            if((defParentElement = [defs objectForKey:data]) == nil) {
                // create the def
                NSXMLElement * element = [[[NSXMLElement alloc] init] autorelease];
                element.name = @"path";
                
                NSDictionary * atts = @{@"d":data,
                                        @"id":[NSString stringWithFormat:@"path-%ld",(++_pathCount)]};
                IJSVGApplyAttributesToElement(atts, element);
                
                // store it against the def
                defs[data] = element;
                defParentElement = element;
            }
            
            // we know at this point, we need to swap out the path to a use
            NSXMLElement * use = [[[NSXMLElement alloc] init] autorelease];
            use.name = @"use";
            
            // grab the id
            NSString * pathId = [defParentElement attributeForName:@"id"].stringValue;
            
            NSXMLNode * useAttribute = [[[NSXMLNode alloc] initWithKind:NSXMLAttributeKind] autorelease];
            useAttribute.name = @"xlink:href";
            useAttribute.stringValue = IJSVGHash(pathId);
            [use addAttribute:useAttribute];
            
            // remove the d attribute
            for(NSXMLNode * attribute in element.attributes) {
                if([attribute.name isEqualToString:@"d"]) {
                    continue;
                }
                [element removeAttributeForName:attribute.name];
                [use addAttribute:attribute];
            }
            
            // swap it out
            [(NSXMLElement *)element.parent replaceChildAtIndex:element.index
                                                       withNode:use];
        }
        
        // add the defs back in
        NSXMLElement * def = [self defElement];
        for(NSXMLElement * defElement in defs.allValues) {
            [def addChild:defElement];
        }
    }
}

- (void)_recursiveParseFromLayer:(IJSVGLayer *)layer
                     intoElement:(NSXMLElement *)element
{
    // is a shape
    if([layer class] == [IJSVGShapeLayer class]) {
        NSXMLElement * child = [self elementForShape:(IJSVGShapeLayer  *)layer
                                          fromParent:element];
        if(child != nil) {
            [element addChild:child];
        }
    } else if([layer isKindOfClass:[IJSVGImageLayer class]]) {
        NSXMLElement * child = [self elementForImage:(IJSVGImageLayer *)layer
                                          fromParent:element];
        if(child != nil) {
            [element addChild:child];
        }
    } else if([layer isKindOfClass:[IJSVGGroupLayer class]]) {
        // assume its probably a group?
        NSXMLElement * child = [self elementForGroup:layer
                                          fromParent:element];
        if(child != nil) {
            [element addChild:child];
        }
    }
}

- (void)applyTransformToElement:(NSXMLElement *)element
                      fromLayer:(IJSVGLayer *)layer
{
    // dont do anything, they are the same
    CGFloat x = layer.frame.origin.x;
    CGFloat y = layer.frame.origin.y;
    
    // check for x or y..they must be included
    if(CGAffineTransformEqualToTransform(layer.affineTransform, CGAffineTransformIdentity) &&
       x == 0.f && y == 0.f) {
        return;
    }
    
    // construct the matrix
    CGAffineTransform transform = layer.affineTransform;
    
    // was there already x and y transform?
    BOOL hasXTransform = transform.tx != 0.f;
    BOOL hasYTransform = transform.ty != 0.f;
    
    // move the x and y position
    if(x != 0.f || y != 0.f) {
        transform = CGAffineTransformConcat( transform, CGAffineTransformMakeTranslation( x, y ));
    }
    
    // x and y were not given so just transform
    if(hasXTransform) {
        transform.tx /= 2.f;
    }
    if(hasYTransform) {
        transform.ty /= 2.f;
    }
    
    // append the string
    NSArray * transformArray = [IJSVGTransform affineTransformToSVGTransformAttributeString:transform];
    NSString * transformStr = [transformArray componentsJoinedByString:@" "];
    
    // apply it to the node
    IJSVGApplyAttributesToElement(@{@"transform":transformStr},element);
}

- (NSXMLElement *)elementForGroup:(IJSVGLayer *)layer
                       fromParent:(NSXMLElement *)parent
{
    // create the element
    NSXMLElement * e = [[[NSXMLElement alloc] init] autorelease];
    e.name = @"g";
    
    // stick defaults
    [self applyDefaultsToElement:e
                       fromLayer:layer];
    
    // add group children
    for(IJSVGLayer * childLayer in layer.sublayers) {
        [self _recursiveParseFromLayer:childLayer
                           intoElement:e];
    }
    
    return e;
}

- (NSString *)base64EncodedStringFromCGImage:(CGImageRef)image
{
    
    // convert the CGImage into an NSImage
    NSBitmapImageRep * rep = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
    
    // work out the data
    NSData * data = [rep representationUsingType:NSBitmapImageFileTypePNG
                                      properties:@{}];
    
    NSString * base64String = [data base64EncodedStringWithOptions:0];
    return [@"data:image/png;base64," stringByAppendingString:base64String];
}

- (void)applyPatternFromLayer:(IJSVGPatternLayer *)layer
                  parentLayer:(IJSVGLayer *)parentLayer
                       stroke:(BOOL)stroke
                    toElement:(NSXMLElement *)element
{
    // now we need the pattern
    IJSVGGroupLayer * patternLayer = (IJSVGGroupLayer *)layer.pattern;
    
    NSXMLElement * patternElement = [self elementForGroup:patternLayer
                                               fromParent:nil];
    patternElement.name = @"pattern";
    
    NSDictionary * dict = @{@"id":[NSString stringWithFormat:@"pattern-%ld",(++_patternCount)],
             @"width":IJSVGShortFloatString(layer.patternNode.width.value),
             @"height":IJSVGShortFloatString(layer.patternNode.height.value)};
    
    IJSVGApplyAttributesToElement(dict, patternElement);
    
    [[self defElement] addChild:patternElement];
    
    // now the use statement
    NSXMLElement * useElement = [[[NSXMLElement alloc] init] autorelease];
    useElement.name = @"use";
    
    // now add the fill
    if(stroke == NO) {
        dict = @{@"fill":IJSVGHashURL([patternElement attributeForName:@"id"].stringValue)};
        IJSVGApplyAttributesToElement(dict, element);
        
        // fill opacity
        if(patternLayer.opacity != 1.f) {
            IJSVGApplyAttributesToElement(@{@"fill-opacity":IJSVGShortFloatString(patternLayer.opacity)}, element);
        }
    } else {
        dict = @{@"stroke":IJSVGHashURL([patternElement attributeForName:@"id"].stringValue)};
        IJSVGApplyAttributesToElement(dict, element);
    }
}

- (void)applyGradientFromLayer:(IJSVGGradientLayer *)layer
                   parentLayer:(IJSVGLayer *)parentLayer
                        stroke:(BOOL)stroke
                     toElement:(NSXMLElement *)element
{
    IJSVGGradient * gradient = layer.gradient;
    NSString * gradKey = [NSString stringWithFormat:@"gradient-%ld",(++_gradCount)];
    NSXMLElement * gradientElement = [[[NSXMLElement alloc] init] autorelease];
    
    // work out linear gradient
    if([gradient isKindOfClass:[IJSVGLinearGradient class]]) {
    
        IJSVGLinearGradient * lGradient = (IJSVGLinearGradient *)gradient;
        gradientElement.name = @"linearGradient";
        NSDictionary * dict = @{@"id":gradKey,
                                @"x1":lGradient.x1.stringValue,
                                @"y1":lGradient.y1.stringValue,
                                @"x2":lGradient.x2.stringValue,
                                @"y2":lGradient.y2.stringValue};
        
        // give it the attibutes
        IJSVGApplyAttributesToElement(dict, gradientElement);
    } else {
        
        // assume radial
        IJSVGRadialGradient * rGradient = (IJSVGRadialGradient *)gradient;
        gradientElement.name = @"radialGradient";
        NSDictionary * dict = @{@"id":gradKey,
                                @"cx":rGradient.cx.stringValue,
                                @"cy":rGradient.cy.stringValue,
                                @"fx":rGradient.fx.stringValue,
                                @"fy":rGradient.fy.stringValue,
                                @"r":rGradient.radius.stringValue};
        
        // give it the attributes
        IJSVGApplyAttributesToElement(dict, gradientElement);
    }
    
    // apply the units
    if(layer.gradient.units == IJSVGUnitUserSpaceOnUse) {
        IJSVGApplyAttributesToElement(@{@"gradientUnits":@"userSpaceOnUse"},
                                      gradientElement);
    }
    
    // add the stops
    NSGradient * grad = layer.gradient.gradient;
    NSInteger noStops = grad.numberOfColorStops;
    for(NSInteger i = 0; i < noStops; i++) {
        
        // grab each color from the gradient
        NSColor * aColor = nil;
        CGFloat location;
        [grad getColor:&aColor
              location:&location
               atIndex:i];
        
        // create the stop element
        NSXMLElement * stop = [[[NSXMLElement alloc] init] autorelease];
        stop.name = @"stop";
        
        NSMutableDictionary * atts = [[[NSMutableDictionary alloc] init] autorelease];
        atts[@"offset"] = [NSString stringWithFormat:@"%g%%",(location*100)];
        
        // add the color
        atts[@"stop-color"] = [IJSVGColor colorStringFromColor:aColor
                                                      forceHex:YES];
        
        // we need to work out the color at this point, annoyingly...
        CGFloat opacity = aColor.alphaComponent;
        atts[@"stop-opacity"] = [NSString stringWithFormat:@"%g",opacity];
        
        // att the attributes
        
        IJSVGApplyAttributesToElement(atts, stop);
        
        // append the stop the gradient
        [gradientElement addChild:stop];
    }
    
    // append it to the defs
    [[self defElement] addChild:gradientElement];
    
    // work out the transform
    NSArray * transforms = layer.gradient.transforms;
    if(transforms.count != 0.f) {
        CGAffineTransform transform = [self affineTransformFromTransforms:transforms];
        
        // work out if there is x and y translate
        BOOL hasXTransform = transform.tx != 0.f;
        BOOL hasYTransform = transform.ty != 0.f;
        
        // x and y were not given so just transform
        if(hasXTransform) {
            transform.tx /= 2.f;
        }
        if(hasYTransform) {
            transform.ty /= 2.f;
        }
        
        // apply the attributes
        NSArray * transforms = [IJSVGTransform affineTransformToSVGTransformAttributeString:transform];
        NSString * tString = [transforms componentsJoinedByString:@" "];
        IJSVGApplyAttributesToElement(@{@"gradientTransform":tString}, gradientElement);
    }
    
    // add it to the element passed in
    if(stroke == NO) {
        IJSVGApplyAttributesToElement(@{@"fill":IJSVGHashURL(gradKey)}, element);
        
        // fill opacity
        if(layer.opacity != 1.f) {
            IJSVGApplyAttributesToElement(@{@"fill-opacity":IJSVGShortFloatString(layer.opacity)}, element);
        }
    } else {
        IJSVGApplyAttributesToElement(@{@"stroke":IJSVGHashURL(gradKey)}, element);
    }
}

- (CGAffineTransform)affineTransformFromTransforms:(NSArray<IJSVGTransform *> *)transforms
{
    CGAffineTransform t = CGAffineTransformIdentity;
    for(IJSVGTransform * transform in transforms) {
        t = CGAffineTransformConcat( t, [transform CGAffineTransform]);
    }
    return t;
}

- (NSXMLElement *)elementForImage:(IJSVGImageLayer *)layer
                       fromParent:(NSXMLElement *)parent
{
    NSString * base64String = [self base64EncodedStringFromCGImage:(CGImageRef)layer.contents];
    
    // image element for the SVG
    NSXMLElement * imageElement = [[[NSXMLElement alloc] init] autorelease];
    imageElement.name = @"image";
    
    NSMutableDictionary * dict =  [[[NSMutableDictionary alloc] init] autorelease];
    dict[@"id"] = [NSString stringWithFormat:@"image-%ld",(++_imageCount)];
    dict[@"width"] = IJSVGShortFloatString(layer.frame.size.width);
    dict[@"height"] = IJSVGShortFloatString(layer.frame.size.height);
    dict[@"xlink:href"] = base64String;
    
    // work out any position
    if(layer.frame.origin.x != 0.f) {
        dict[@"x"] = IJSVGShortFloatString(layer.frame.origin.x);
    }
    if(layer.frame.origin.y != 0.f) {
        dict[@"y"] = IJSVGShortFloatString(layer.frame.origin.y);
    }
    
    // add the attributes
    IJSVGApplyAttributesToElement(dict, imageElement);
    return imageElement;
}

- (NSXMLElement *)elementForShape:(IJSVGShapeLayer  *)layer
                       fromParent:(NSXMLElement *)parent
{
    NSXMLElement * e = [[[NSXMLElement alloc] init] autorelease];
    e.name = @"path";
    CGPathRef path = layer.path;
    
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    
    // path
    dict[@"d"] = [self pathFromCGPath:path];
    
    // work out even odd rule
    if([layer.fillRule isEqualToString:kCAFillRuleNonZero] == NO) {
        dict[@"fill-rule"] = @"evenodd";
    }
    
    // fill color
    if(layer.fillColor != nil) {
        NSColor * fillColor = [NSColor colorWithCGColor:layer.fillColor];
        NSString * colorString = [IJSVGColor colorStringFromColor:fillColor];
        
        // could be none
        if(colorString != nil) {
            dict[@"fill"] = colorString;
        }
    }
    
    // is there a gradient fill?
    if(layer.gradientFillLayer != nil) {
        [self applyGradientFromLayer:layer.gradientFillLayer
                         parentLayer:(IJSVGLayer *)layer
                              stroke:NO
                           toElement:e];
    }
    
    // is there a pattern?
    if(layer.patternFillLayer != nil) {
        [self applyPatternFromLayer:layer.patternFillLayer
                        parentLayer:(IJSVGLayer *)layer
                             stroke:NO
                          toElement:e];
    }
    
    // is there a stroke layer?
    if(layer.strokeLayer != nil) {
        // check the type
        IJSVGStrokeLayer * strokeLayer = layer.strokeLayer;
        if([strokeLayer isKindOfClass:[IJSVGShapeLayer  class]]) {
            // stroke
            if(strokeLayer.lineWidth != 0.f) {
                dict[@"stroke-width"] = IJSVGShortFloatString(strokeLayer.lineWidth);
            }
            
            // stroke gradient
            if(layer.gradientStrokeLayer != nil) {
                [self applyGradientFromLayer:layer.gradientStrokeLayer
                                 parentLayer:(IJSVGPatternLayer *)layer
                                      stroke:YES
                                   toElement:e];
                
            } else if(layer.patternStrokeLayer != nil) {
                // stroke pattern
                [self applyPatternFromLayer:layer.patternStrokeLayer
                                parentLayer:(IJSVGPatternLayer *)layer
                                     stroke:YES
                                  toElement:e];
            
            } else if(strokeLayer.strokeColor != nil) {
                NSColor * strokeColor = [NSColor colorWithCGColor:strokeLayer.strokeColor];
                NSString * strokeColorString = [IJSVGColor colorStringFromColor:strokeColor];
                
                // could be none
                if(strokeColorString != nil) {
                    dict[@"stroke"] = strokeColorString;
                }
            }
            
            // work out line cap
            if([strokeLayer.lineCap isEqualToString:kCALineCapButt] == NO) {
                NSString * capStyle = nil;
                if([strokeLayer.lineCap isEqualToString:kCALineCapRound]) {
                    capStyle = @"round";
                } else if([strokeLayer.lineCap isEqualToString:kCALineCapSquare]) {
                    capStyle = @"square";
                }
                if(capStyle != nil) {
                    dict[@"stroke-linecap"] = capStyle;
                }
            }
            
            // work out line join
            if([strokeLayer.lineJoin isEqualToString:kCALineJoinMiter] == NO) {
                NSString * joinStyle = nil;
                if([strokeLayer.lineJoin isEqualToString:kCALineJoinBevel]) {
                    joinStyle = @"bevel";
                } else if([strokeLayer.lineJoin isEqualToString:kCALineJoinRound]) {
                    joinStyle = @"round";
                }
                if(joinStyle != nil) {
                    dict[@"stroke-linejoin"] = joinStyle;
                }
            }
            
            // work out dash offset...
            if(strokeLayer.lineDashPhase != 0.f) {
                dict[@"stroke-dashoffset"] = IJSVGShortFloatString(strokeLayer.lineDashPhase);
            }
            
            // work out dash array
            if(strokeLayer.lineDashPattern.count != 0) {
                dict[@"stroke-dasharray"] = [strokeLayer.lineDashPattern componentsJoinedByString:@" "];
            }
            
        }
    }

    // apply the attributes
    IJSVGApplyAttributesToElement(dict, e);
    
    // apple defaults
    [self applyDefaultsToElement:e
                       fromLayer:(IJSVGLayer *)layer];
    return e;
}

- (void)applyDefaultsToElement:(NSXMLElement *)element
                     fromLayer:(IJSVGLayer *)layer
{
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    
    // opacity
    if(layer.opacity != 1.f) {
        dict[@"opacity"] = IJSVGShortFloatString(layer.opacity);
    }
    
    // blendmode - we only every apply a stylesheet blend mode
    if(layer.blendingMode != kCGBlendModeNormal) {
        NSString * str = [IJSVGUtils mixBlendingModeForBlendMode:(IJSVGBlendMode)layer.blendingMode];
        if(str != nil) {
            dict[@"style"] = [NSString stringWithFormat:@"mix-blend-mode:%@",str];
        }
    }
    
    
    // add atttributes
    IJSVGApplyAttributesToElement(dict, element);
    
    // apply transforms
    [self applyTransformToElement:element
                        fromLayer:layer];
    
    // add any masks...
    if(layer.mask != nil) {
        [self applyMaskToElement:element
                       fromLayer:layer];
    }
}

- (void)applyMaskToElement:(NSXMLElement *)element
                 fromLayer:(IJSVGLayer *)layer
{
    // create the element
    NSXMLElement * mask = [[[NSXMLElement alloc] init] autorelease];
    mask.name = @"mask";
    
    // create the key
    NSString * maskKey = [NSString stringWithFormat:@"mask-%ld",(++_maskCount)];
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    dict[@"id"] = maskKey;
    dict[@"maskContentUnits"] = @"userSpaceOnUse";
    dict[@"maskUnits"] = @"objectBoundingBox";
    
    if(layer.mask.frame.origin.x != 0.f) {
        dict[@"x"] = IJSVGShortFloatString(layer.mask.frame.origin.x);
    }
    if(layer.mask.frame.origin.y != 0.f) {
        dict[@"y"] = IJSVGShortFloatString(layer.mask.frame.origin.y);
    }
    
    IJSVGApplyAttributesToElement(dict, mask);
    
    // add the cool stuff
    [self _recursiveParseFromLayer:(IJSVGLayer *)layer.mask
                       intoElement:mask];
    
    // add mask id to element
    IJSVGApplyAttributesToElement(@{@"mask":IJSVGHashURL(maskKey)}, element);
    
    // add it defs
    [[self defElement] addChild:mask];
}

- (NSString *)SVGString
{
    return [_dom XMLStringWithOptions:NSXMLNodePrettyPrint];
}

- (NSData *)SVGData
{
    return [[self SVGString] dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark CGPath stuff

- (NSString *)pathFromCGPath:(CGPathRef)path
{
    // string to store the path in
    NSArray * instructions = [IJSVGExporterPathInstruction instructionsFromPath:path];
    
    // work out what to do...
    if((_options & IJSVGExporteroptionCleanupPaths) != 0) {
        [IJSVGExporterPathInstruction convertInstructionsToRelativeCoordinates:instructions];
    }
    return [IJSVGExporterPathInstruction pathStringFromInstructions:instructions];
}

void IJSVGExporterPathCaller(void * info, const CGPathElement * pathElement) {
    IJSVGCGPathHandler handler = (IJSVGCGPathHandler)info;
    handler(pathElement);
};

- (void)sortAttributesOnElement:(NSXMLElement *)element
{
    const NSArray * order = @[@"id",@"width",@"height",@"x",@"x1",@"x2",
                              @"y",@"y1",@"y2",@"cx",@"cy",@"r",@"fill",
                              @"stroke",@"marker",@"d",@"points",@"transform",
                              @"gradientTransform", @"xlink:href"];
    
    // grab the attributes
    NSArray<NSXMLNode *>* attributes = element.attributes;
    NSInteger count = attributes.count;
    
    // sort the attributes using a custom sort
    NSArray * sorted = [attributes sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        // tell compiler we are nodes
        NSXMLNode * attribute1 = (NSXMLNode *)obj1;
        NSXMLNode * attribute2 = (NSXMLNode *)obj2;
        
        // base index
        float aIndex = count;
        float bIndex = count;
        
        // loop around each order string
        for(NSInteger i = 0; i < order.count; i++) {
            if([attribute1.name isEqualToString:order[i]]) {
                aIndex = i;
            } else if([attribute1.name rangeOfString:[order[i] stringByAppendingString:@"-"]].location == 0) {
                aIndex = i + .5;
            }
            if([attribute2.name isEqualToString:order[i]]) {
                bIndex = i;
            } else if([attribute2.name rangeOfString:[order[i] stringByAppendingString:@"-"]].location == 0) {
                bIndex = i + .5;
            }
        }
        
        // return the comparison set
        if(aIndex != bIndex) {
            if(aIndex > bIndex) {
                return NSOrderedDescending;
            } else {
                return NSOrderedAscending;
            }
        }
        return [attribute1.name compare:attribute2.name];
    }];
    
    // remove all attributes
    for(NSXMLNode * node in attributes) {
        [element removeAttributeForName:node.name];
    }
    
    // add them back on in order
    for(NSXMLNode * attribute in sorted) {
        [element addAttribute:attribute];
    }
    
}

@end
