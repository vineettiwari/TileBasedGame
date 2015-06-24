//
//  GameScene.m
//  ErrorCrawl
//
//  Created by Vineet Tiwari on 2015-06-21.
//  Copyright (c) 2015 vinny.co. All rights reserved.
//

#import "LevelScene.h"
#import "SKTAudio.h"
#import "ParallaxNode.h"
#import "JSTileMap+TileLocations.h"
#import "Player.h"
#import "HUDNode.h"
#import "SharedTextureCache.h"
#import "Crawler.h"

@interface LevelScene ()

@property (nonatomic, assign) NSUInteger currentLevel;
@property (nonatomic, strong) SKNode *gameNode;
@property (nonatomic, strong) JSTileMap *map;
@property (nonatomic, strong) Player *player;
@property (nonatomic, assign) NSTimeInterval previousUpdateTime;
@property (nonatomic, strong) TMXLayer *walls;
@property (nonatomic, strong) HUDNode *hud;
@property (nonatomic, strong) NSMutableArray *enemies;

@end

@implementation LevelScene

- (id)initWithSize:(CGSize)size level:(NSUInteger)currentLevel {
  if ((self = [super initWithSize:size])) {
    self.currentLevel = 1;

    NSString *path = [[NSBundle mainBundle] pathForResource:@"levels" ofType:@"plist"];
    NSDictionary *allLevelsDict = [NSDictionary dictionaryWithContentsOfFile:path];

    NSString *levelString = [NSString stringWithFormat:@"level%ld", (long)self.currentLevel];
    NSDictionary *levelDict = allLevelsDict[levelString];

    NSString *musicFilename = levelDict[@"music"];
    [[SKTAudio sharedInstance] playBackgroundMusic:musicFilename];

    self.gameNode = [SKNode node];
    [self addChild:self.gameNode];

    [self loadParallaxBackground:levelDict];

    NSString *levelName = [levelDict objectForKey:@"level"];
    self.map = [JSTileMap mapNamed:levelName];
    [self.gameNode addChild:self.map];

    self.walls = [self.map layerNamed:@"walls"];

    SKTextureAtlas *atlas = [SKTextureAtlas atlasNamed:@"assets"];
    for (NSString *textureName in [atlas textureNames]) {
      SKTexture *texture = [atlas textureNamed:textureName];
      [[SharedTextureCache sharedCache] addTexture:texture name:textureName];
    }

    self.player = [[Player alloc] initWithImageNamed:@"Player1"];
    self.player.zPosition = 900;
    [self.map addChild:self.player];

    TMXObjectGroup *objects = [self.map groupNamed:@"objects"];
    NSDictionary *playerObj = [objects objectNamed:@"player"];
    self.player.position = CGPointMake([playerObj[@"x"] floatValue], [playerObj[@"y"] floatValue]);

    [self loadEnemies];

    self.hud = [[HUDNode alloc] initWithSize:size];
    [self addChild:self.hud];
    self.hud.zPosition = 1000;

    self.player.hud = self.hud;
  }
  return self;
}

- (void)loadEnemies {
  self.enemies = [NSMutableArray array];

  TMXObjectGroup *enemiesGroup = [self.map groupNamed:@"enemies"];
  for (NSDictionary *enemyDict in enemiesGroup.objects) {
    //1
    NSString *enemyType = enemyDict[@"type"];
    NSString *firstFrameName = [NSString stringWithFormat:@"%@1.png", enemyType];
    // 2
    Enemy *enemy = [[NSClassFromString(enemyType) alloc] initWithImageNamed:firstFrameName];

    enemy.position = CGPointMake([enemyDict[@"x"] floatValue], [enemyDict[@"y"] floatValue]);

    //3
    enemy.player = self.player;

    [self.map addChild:enemy];
    enemy.zPosition = 900;
    [self.enemies addObject:enemy];
  }
}

- (void)loadParallaxBackground:(NSDictionary *)levelDict {
  ParallaxNode *parallaxNode = [ParallaxNode node];

  NSArray *backgroundArray = levelDict[@"background"];

  for (NSArray *layerArray in backgroundArray) {

    CGFloat indexOfLayer = [backgroundArray indexOfObject:layerArray] + 1.0;
    CGFloat ratio = (4.0 - indexOfLayer) / 8.0;
    if (indexOfLayer == 4.0) {
      ratio = 0.0;
    }

    for (NSString *chunkFilename in layerArray) {

      SKSpriteNode *backgroundSprite = [SKSpriteNode spriteNodeWithImageNamed:chunkFilename];
      backgroundSprite.anchorPoint = CGPointMake(0.0, 0.0);

      NSInteger indexOfChunk = [layerArray indexOfObject:chunkFilename];

      [parallaxNode addChild:backgroundSprite z:-indexOfLayer parallaxRatio:CGPointMake(ratio, 0.6) positionOffset:CGPointMake(indexOfChunk * 1024, 30)];
    }
  }

  [self.gameNode addChild:parallaxNode];
  parallaxNode.name = @"parallax";
  parallaxNode.zPosition = -1000;
}

- (void)update:(NSTimeInterval)currentTime {
  NSTimeInterval delta = currentTime - self.previousUpdateTime;
  self.previousUpdateTime = currentTime;
  if (delta > 0.1) {
    delta = 0.1;
  }

  [self.player update:delta];
  [self checkForAndResolveCollisions:self.player forLayer:self.walls];

  NSMutableArray *enemiesThatNeedDeleting;

  for (Enemy *enemy in self.enemies) {
    [enemy update:delta];
    if (enemy.isActive) {
      [self checkForAndResolveCollisions:enemy forLayer:self.walls];
      [self checkForEnemyCollisions:enemy];
    }

    if (!enemy.isActive && enemy.characterState == kStateDead) {
      if (enemiesThatNeedDeleting == nil) {
        enemiesThatNeedDeleting = [NSMutableArray array];
      }
      [enemiesThatNeedDeleting addObject:enemy];
    }
  }

  for (Enemy *enemyToDelete in enemiesThatNeedDeleting) {
    [self.enemies removeObject:enemyToDelete];
    [enemyToDelete removeFromParent];
  }

  [self setViewpointCenter:self.player.position];
}

- (void)checkForAndResolveCollisions:(Character *)character forLayer:(TMXLayer *)layer {
  character.onGround = NO;
  character.onWall = NO;

  NSInteger indices[8] = {7, 1, 3, 5, 0, 2, 6, 8};

  for (NSUInteger i = 0; i < 8; i++) {
    NSInteger tileIndex = indices[i];

    CGRect characterRect = [character collisionBoundingBox];
    CGPoint characterCoord = [self.walls coordForPoint:character.position];

    NSInteger tileColumn = tileIndex % 3;
    NSInteger tileRow = tileIndex / 3;
    CGPoint tileCoord = CGPointMake(characterCoord.x + (tileColumn - 1), characterCoord.y + (tileRow - 1));

    NSInteger gid = [self.walls tileGIDAtTileCoord:tileCoord];
    if (gid != 0) {
      CGRect tileRect = [self.map tileRectFromTileCoords:tileCoord];
      if (CGRectIntersectsRect(characterRect, tileRect)) {
        CGRect intersection = CGRectIntersection(characterRect, tileRect);
        if (tileIndex == 7) {
          //tile is directly below the character
          character.desiredPosition = CGPointMake(character.desiredPosition.x, character.desiredPosition.y + intersection.size.height);
          character.velocity = CGPointMake(character.velocity.x, 0.0);
          character.onGround = YES;
        } else if (tileIndex == 1) {
          //tile is directly above the character
          character.desiredPosition = CGPointMake(character.desiredPosition.x, character.desiredPosition.y - intersection.size.height);
          character.velocity = CGPointMake(character.velocity.x, 0.0);
        } else if (tileIndex == 3) {
          //tile is left of the character
          character.desiredPosition = CGPointMake(character.desiredPosition.x + intersection.size.width, character.desiredPosition.y);
          character.onWall = YES;
          character.velocity = CGPointMake(0.0, character.velocity.y);
        } else if (tileIndex == 5) {
          //tile is right of the character
          character.desiredPosition = CGPointMake(character.desiredPosition.x - intersection.size.width, character.desiredPosition.y);
          character.onWall = YES;
          character.velocity = CGPointMake(0.0, character.velocity.y);
        } else {
          if (intersection.size.width > intersection.size.height) {
            //tile is diagonal, but resolving collision vertically
            CGFloat resolutionHeight;
            if (tileIndex > 4) {
              resolutionHeight = intersection.size.height;
              if (character.velocity.y < 0) {
                character.velocity = CGPointMake(character.velocity.x, 0.0);
                character.onGround = YES;
              }
            } else {
              resolutionHeight = -intersection.size.height;
              if (character.velocity.y > 0) {
                character.velocity = CGPointMake(character.velocity.x, 0.0);
              }
            }
            character.desiredPosition = CGPointMake(character.desiredPosition.x, character.desiredPosition.y + resolutionHeight);
          } else {
            //tile is diagonal, but resolving horizontally
            CGFloat resolutionWidth;
            if (tileIndex == 6 || tileIndex == 0) {
              resolutionWidth = intersection.size.width;
            } else {
              resolutionWidth = -intersection.size.width;
            }
            character.desiredPosition = CGPointMake(character.desiredPosition.x + resolutionWidth, character.desiredPosition.y);

            if (tileIndex == 6 || tileIndex == 8) {
              character.onWall = YES;
            }
            character.velocity = CGPointMake(0.0, character.velocity.y);
          }
        }
      }
    }
    character.position = character.desiredPosition;
  }
}

- (void)setViewpointCenter:(CGPoint)position {
  NSInteger x = MAX(position.x, self.size.width / 2);
  NSInteger y = MAX(position.y, self.size.height / 2);
  x = MIN(x, (self.map.mapSize.width * self.map.tileSize.width) - self.size.width / 2);
  y = MIN(y, (self.map.mapSize.height * self.map.tileSize.height) - self.size.height / 2);
  CGPoint actualPosition = CGPointMake(x, y);
  CGPoint centerOfView = CGPointMake(self.size.width/2, self.size.height/2);
  CGPoint viewPoint = CGPointSubtract(centerOfView, actualPosition);
  self.gameNode.position = viewPoint;
}

- (void)checkForEnemyCollisions:(Enemy *)enemy {
  if (enemy.isActive && self.player.isActive) {
    if (CGRectIntersectsRect(self.player.collisionBoundingBox, enemy.collisionBoundingBox)) {
      CGPoint playerFootPoint = CGPointMake(self.player.position.x, self.player.position.y - self.player.collisionBoundingBox.size.height / 2);
      if (self.player.velocity.y < 0 && playerFootPoint.y > enemy.position.y) {
        [self.player bounce];
        [enemy tookHit:self.player];
      } else {
        [self.player tookHit:enemy];
      }
    }
  }
}

@end
