/*
Sniper Arena v0.8.9 aimbot source code.
Made by shmoo.
Function naming conventions:
    ClassName_FunctionName(arguments)
...for easy reference in the included dump.
*/

#import "Macros.h"
#import "Config.h"
#import <substrate.h>
#import <mach-o/dyld.h>

uint64_t getRealOffset(uint64_t);

struct me_t {
	void *object;
	void *camera;
	Vector3 location;
	int team;
};

struct target_t {
	void *object;
	Vector3 location;
	double health;
	float distanceFromMe;
};

me_t *me;
target_t *currentTarget;

Quaternion lookRotation;

void *(*Component_GetTransform)(void *component) = (void *(*)(void *))getRealOffset(0x10079DDD8);
void (*Transform_INTERNAL_GetPosition)(void *transform, Vector3 *out) = (void (*)(void *, Vector3 *))getRealOffset(0x1007E7ACC);

bool compareVectorsWithTolerance(Vector3 first, Vector3 second, float tolerance){
	float firstXSubbed = first.x - tolerance;
	float firstXAdded = first.x + tolerance;
	
	float firstYSubbed = first.y - tolerance;
	float firstYAdded = first.y + tolerance;
	
	float firstZSubbed = first.z - tolerance;
	float firstZAdded = first.z + tolerance;
	
	bool secondXFallsBetween = second.x >= firstXSubbed && second.x <= firstXAdded;
	bool secondYFallsBetween = second.y >= firstYSubbed && second.y <= firstYAdded;
	bool secondZFallsBetween = second.z >= firstZSubbed && second.z <= firstZAdded;
	
	return secondXFallsBetween && secondYFallsBetween && secondZFallsBetween;
}

void (*GameEnemy_Update)(void *gameEnemy);

void _GameEnemy_Update(void *gameEnemy){
	if(!me){
		me = new me_t();
	}
	else if(!currentTarget){
		currentTarget = new target_t();
	}
	else{
		if(me->camera){
			Vector3 gameEnemyLocation;
			
			Transform_INTERNAL_GetPosition(Component_GetTransform(gameEnemy), &gameEnemyLocation);

			if(compareVectorsWithTolerance(me->location, gameEnemyLocation, 4.0f)){
				me->object = gameEnemy;
				me->team = *(int *)((uint64_t)me->object + 0x48);
			}
		}

		if(me->object && me->object != gameEnemy){
			bool differentTeam = me->team != *(int *)((uint64_t)gameEnemy + 0x48);
			double health = *(double *)((uint64_t)gameEnemy + 0x60);
			bool alive = health > 1;

			if(!currentTarget->object){
				if(differentTeam && alive){
					currentTarget->object = gameEnemy;
					currentTarget->health = health;

					Transform_INTERNAL_GetPosition(Component_GetTransform(currentTarget->object), &currentTarget->location);
					
					currentTarget->distanceFromMe = Vector3::distance(me->location, currentTarget->location);
				}
				
				GameEnemy_Update(gameEnemy);
				
				return;
			}
			else{
				if(currentTarget->health < 1){
					currentTarget = NULL;
					
					GameEnemy_Update(gameEnemy);
					
					return;
				}

				if(gameEnemy == currentTarget->object){
					currentTarget->health = *(double *)((uint64_t)currentTarget->object + 0x60);

					Transform_INTERNAL_GetPosition(Component_GetTransform(currentTarget->object), &currentTarget->location);
					
					currentTarget->distanceFromMe = Vector3::distance(me->location, currentTarget->location);
				}

				Vector3 potentialTargetLocation;
				Transform_INTERNAL_GetPosition(Component_GetTransform(gameEnemy), &potentialTargetLocation);
				
				float potentialEnemyDistanceFromMe = Vector3::distance(me->location, potentialTargetLocation);
				
				if(differentTeam && alive && potentialEnemyDistanceFromMe < currentTarget->distanceFromMe){
					currentTarget->object = gameEnemy;
					currentTarget->health = health;
					currentTarget->location = potentialTargetLocation;
					currentTarget->distanceFromMe = potentialEnemyDistanceFromMe;
				}

				lookRotation = Quaternion::LookRotation((currentTarget->location + Vector3(0, [SliderHook getSliderValueForHook:@"Y Value Adjustment"], 0)) - me->location, Vector3(0, 1, 0));
			}
		}
	}
	
	GameEnemy_Update(gameEnemy);
}

void (*GameEnemyFinder_Update)(void *gameEnemyFinder);

void _GameEnemyFinder_Update(void *gameEnemyFinder){
	if(!me){
		me = new me_t();
	}
	else{
		void *mainCamera = *(void **)((uint64_t)gameEnemyFinder + 0x20);

		if(mainCamera){
			me->camera = mainCamera;
		}
	}
	
	GameEnemyFinder_Update(gameEnemyFinder);
}

void (*GameLooking_Start)(void *gameLooking) = (void (*)(void *))getRealOffset(0x100250778);

void (*GameLooking_Update)(void *gameLooking);

void _GameLooking_Update(void *gameLooking){
	*(Quaternion *)((uint64_t)gameLooking + 0x50) = lookRotation;
	
	GameLooking_Update(gameLooking);
	GameLooking_Start(gameLooking);
}

%ctor {
	MSHookFunction((void *)getRealOffset(0x10024D990), (void *)_GameEnemy_Update, (void **)&GameEnemy_Update);
	MSHookFunction((void *)getRealOffset(0x10024E87C), (void *)_GameEnemyFinder_Update, (void **)&GameEnemyFinder_Update);
	MSHookFunction((void *)getRealOffset(0x100250B04), (void *)_GameLooking_Update, (void **)&GameLooking_Update);
}

uint64_t getRealOffset(uint64_t offset){
    return _dyld_get_image_vmaddr_slide(0)+offset;
}