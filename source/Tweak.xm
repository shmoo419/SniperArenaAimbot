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

/*
If you don't understand why I'm comparing Vector3's this way, go here:
https://noobtuts.com/cpp/compare-float-values

Returns true if second falls in bounds with first.
*/
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

/*
Even though this class is called GameEnemy, it handles every player object in the match, including ours.
When you're making an aimbot, remember to test every function from every class that catches your eye.
*/
void _GameEnemy_Update(void *gameEnemy){
	if(!me){
		me = new me_t();
	}
	else if(!currentTarget){
		currentTarget = new target_t();
	}
	else{
		/*
		My player object should be where my camera is.
		If you cannot find a way to get your player object, or you cannot find a way to differentiate the other objects from your object, this way is fine.
		You just need to make sure that what you think is your camera is actually your camera.
		I made sure my camera was my camera by setting its field of view to 90.
		*/
		if(me->camera){
			/* Get the location of where our camera is, and initialize me->location with it. */
			Transform_INTERNAL_GetPosition(Component_GetTransform(me->camera), &me->location);
			
			/*
			We have to find our player object now. Why?
			To make sure that we don't aim at ourselves. This aimbot is based on distance.
			Every GameEnemy object, including ours, passes through this function. We just have to find it.
			No sense in doing this when my camera is NULL because me->location won't be initialized.
			*/	
			Vector3 gameEnemyLocation;
			
			Transform_INTERNAL_GetPosition(Component_GetTransform(gameEnemy), &gameEnemyLocation);
			
			/*
			There is a very large chance our camera will not be at the exact same location we are.
			However, it is close enough to us so that we're able to get our real object.
			*/
			if(compareVectorsWithTolerance(me->location, gameEnemyLocation, 4.0f)){
				me->object = gameEnemy;
				
				/* Since we have our player object, we can safely get our team. */
				me->team = *(int *)((uint64_t)me->object + 0x48);
			}
		}
		
		/*
		The main aimbot code starts here.
		Obviously, we don't want to examine our player object when doing this. We only want to pull data from it.
		Taking advantage of short circuiting here.
		*/
		if(me->object && me->object != gameEnemy){
			/*
			Choose someone to lock onto.
			Conditions:
				- cannot be on my team
				- cannot be dead
			*/
			
			bool differentTeam = me->team != *(int *)((uint64_t)gameEnemy + 0x48);
			double health = *(double *)((uint64_t)gameEnemy + 0x60);
			bool alive = health > 1;
			
			/*
			In order to save a headache in the future for this first search, just find someone. 
			We know we haven't found anyone if currentTarget's object is NULL.
			*/	
			if(!currentTarget->object){
				if(differentTeam && alive){
					/* We found someone! */
					currentTarget->object = gameEnemy;
					currentTarget->health = health;
					
					/* In case you miss this line, we are initializing currentTarget->location. */
					Transform_INTERNAL_GetPosition(Component_GetTransform(currentTarget->object), &currentTarget->location);
					
					currentTarget->distanceFromMe = Vector3::distance(me->location, currentTarget->location);
				}
				
				GameEnemy_Update(gameEnemy);
				
				return;
			}
			else{
				/*
				Do not aim at a dead enemy.
				Start a new search right away if this is the case.
				*/
				if(currentTarget->health < 1){
					currentTarget = NULL;
					
					GameEnemy_Update(gameEnemy);
					
					return;
				}
				
				/* currentTarget->object is initialized, so update the the data for it. */
				if(gameEnemy == currentTarget->object){
					currentTarget->health = *(double *)((uint64_t)currentTarget->object + 0x60);
					
					/*
					In this game, you don't move from where you are.
					This line is just for safety because you can't assume anything when making this kind of thing.
					*/
					Transform_INTERNAL_GetPosition(Component_GetTransform(currentTarget->object), &currentTarget->location);
					
					currentTarget->distanceFromMe = Vector3::distance(me->location, currentTarget->location);
				}
				
				/*
				Try and find someone new to lock onto.
				We are using the differentTeam and health variables from above.
				Why? No sense in pulling the exact same data twice.
				*/
				Vector3 potentialTargetLocation;
				Transform_INTERNAL_GetPosition(Component_GetTransform(gameEnemy), &potentialTargetLocation);
				
				float potentialEnemyDistanceFromMe = Vector3::distance(me->location, potentialTargetLocation);
				
				if(differentTeam && alive && potentialEnemyDistanceFromMe < currentTarget->distanceFromMe){
					/*
					We found someone new!
					Update the values for currentTarget to make the rotation.
					*/
					currentTarget->object = gameEnemy;
					currentTarget->health = health;
					currentTarget->location = potentialTargetLocation;
					currentTarget->distanceFromMe = potentialEnemyDistanceFromMe;
				}
				
				/*
				Make the rotation to face currentTarget.
				Watch the video in README.md to get know what [SliderHook getSliderValueForHook:@"Y Value Adjustment"] is used for.
				There's also no point of including the mod menu setup code in this, so just pretend it is there.
				*/
				lookRotation = Quaternion::LookRotation((currentTarget->location + Vector3(0, [SliderHook getSliderValueForHook:@"Y Value Adjustment"], 0)) - me->location, Vector3(0, 1, 0));
			}
		}
	}
	
	GameEnemy_Update(gameEnemy);
}

void (*GameEnemyFinder_Update)(void *gameEnemyFinder);

/*
This function is hooked just so I have a way of getting the main camera for my player object.
For some reason I wasn't able to get my camera with Unity's functions.
*/
void _GameEnemyFinder_Update(void *gameEnemyFinder){
	if(!me){
		me = new me_t();
	}
	else{
		void *mainCamera = *(void **)((uint64_t)gameEnemyFinder + 0x20);
		
		/* We don't want a NULL camera. */
		if(mainCamera){
			me->camera = mainCamera;
		}
	}
	
	GameEnemyFinder_Update(gameEnemyFinder);
}

void (*GameLooking_Start)(void *gameLooking) = (void (*)(void *))getRealOffset(0x100250778);

void (*GameLooking_Update)(void *gameLooking);

/*
When you are in game, the map is represented by a 2D plane as far as rotations are concerned, and our rotation is represented by a vector.
In the rotation vector:
	- x = x coordinate
	- y = y coordinate
	- z = rotation acceleration (slows down over time, think mouse acceleration)

Because of this, I thought it was impossible to make an aimbot for this game.
*/
void _GameLooking_Update(void *gameLooking){
	*(Quaternion *)((uint64_t)gameLooking + 0x50) = lookRotation;
	
	GameLooking_Update(gameLooking);
	
	/*
	After an *extremely* long time of analysis, I determined that I have no chance of changing defaultRotation (the instance variable at gameLooking+0x50) AND having those changes take effect in game.
	After analyzing most of the functions in the GameLooking class, I figured out that the only place defaultRotation's value is ever used is in GameLooking::Start.
	This is a very dirty hack because Start should only be called once before Update is called on any script in Unity. But it works.
	From the Unity docs: "Start is called exactly once in the lifetime of the script."
	*/
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
