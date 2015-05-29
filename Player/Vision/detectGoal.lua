require('Config');	-- For Ball and Goal Size
require('HeadTransform');	-- For Projection
require('Body')

--Use tilted boundingbox? (robots with nonzero bodytilt)
use_tilted_bbox = Config.vision.use_tilted_bbox or 0;
--Use center post to determine post type (disabled for OP)
use_centerpost=Config.vision.goal.use_centerpost or 0;
--Check the bottom of the post for green
check_for_ground = Config.vision.goal.check_for_ground or 0;
--Min height of goalpost (to reject false positives at the ground)
goal_height_min = Config.vision.goal.height_min or -0.5;
goal_height_max = Config.vision.goal.height_max or 1.3
---Detects a goal of a given color.
--@param color The color to use for detection, represented by an int
--@return Table containing whether a ball was detected
--If a goal is detected, also contains additional stats about the goal

--print("DFY:",Config.vision.goal.distanceFactorYellow)

if Config.game.playerID >1  then
  distanceFactorYellow = Config.vision.goal.distanceFactorYellow or 1.0
else
  distanceFactorYellow = Config.vision.goal.distanceFactorYellowGoalie or 1
end
	
--Post dimension
postDiameter = Config.world.postDiameter or 0.10;
postHeight = Config.world.goalHeight or 0.80;
goalWidth = Config.world.goalWidth or 1.40;

--------------------------------------------------------------
--Vision threshold values (to support different resolutions)
--------------------------------------------------------------
th_min_color_count=Config.vision.goal.th_min_color_count;
th_min_area = Config.vision.goal.th_min_area;
th_nPostB = Config.vision.goal.th_nPostB;
th_min_orientation = Config.vision.goal.th_min_orientation;
th_min_fill_extent = Config.vision.goal.th_min_fill_extent;
th_aspect_ratio = Config.vision.goal.th_aspect_ratio;
th_edge_margin = Config.vision.goal.th_edge_margin;
th_bottom_boundingbox = Config.vision.goal.th_bottom_boundingbox;
th_ground_boundingbox = Config.vision.goal.th_ground_boundingbox;
th_min_green_ratio = Config.vision.goal.th_min_green_ratio;
th_goal_separation = Config.vision.goal.th_goal_separation;
th_min_area_unknown_post = Config.vision.goal.th_min_area_unknown_post;

--function detect(color)
local function update(self, color, p_vision)
  self.detect = 0;
  local postB;

  if use_tilted_bbox>0 then
    --old code on tilted bbox 
    --deleted for conciseness
    print('Error! Nao Robots do not deal with tilted GoalPost')
  else
    tiltAngle=0;
    vcm.set_camera_rollAngle(tiltAngle);
    --params: label data; w; h; 
    --optinal params: min_width; max_width; connect_th; max_gap; min_height 
    postB = ImageProc.goal_posts_white(p_vision.labelB.data,
      p_vision.labelB.m, p_vision.labelB.n, 2, 20, 0.4);
  end

  local function compare_post_area(post1, post2)
    return post1.area > post2.area
  end

  if (not postB) then 	
    p_vision:add_debug_message("No post detected\n")
    return; 
  end

  table.sort(postB, compare_post_area)

  local npost = 0;
  local ivalidB = {};
  local postA = {};
  p_vision:add_debug_message(string.format("Checking %d posts\n",#postB));

  lower_factor = 0.3;
  for i = 1,#postB do
    p_vision:add_debug_message(string.format("===== Post No. %d =====\n", i));
    p_vision:add_debug_message(string.format("l=%d,r=%d,t=%d,b=%d; x=%d,y=%d\n",
      postB[i].boundingBox[1],postB[i].boundingBox[2],postB[i].boundingBox[3],
      postB[i].boundingBox[4],postB[i].centroid[1],postB[i].centroid[2]));

    local valid = true;

    --Check lower part of the goalpost for thickness
    
    scaleBGoal = p_vision.scaleB
    if use_tilted_bbox>0 then
      print('Error! Nao Robots do not deal with tilted GoalPost')
    else
      local bboxA = vcm.bboxStats(color,postB[i].boundingBox,_,scaleBGoal);
      postStats = ImageProc.color_stats(p_vision.labelA.data, p_vision.labelA.m, 
                                        p_vision.labelA.n, color, bboxA);
      boundingBoxLower={};
      boundingBoxLower[1],boundingBoxLower[2],
      boundingBoxLower[3],boundingBoxLower[4]=
        postB[i].boundingBox[1], postB[i].boundingBox[2],
        postB[i].boundingBox[3], postB[i].boundingBox[4];
      boundingBoxLower[3] = (1-lower_factor)* boundingBoxLower[3] + lower_factor*boundingBoxLower[4];
      local bboxA = vcm.bboxStats(color, postB[i].boundingBox,tiltAngle,scaleBGoal);
      --postStatsLow = ImageProc.color_stats(p_vision.labelA.data, p_vision.labelA.m, 
      --                                  p_vision.labelA.n, color, bboxA);
    end
    --Area Check
    if (postStats.area < th_min_area) then
      p_vision:add_debug_message(string.format("Area check fail: %.2f\n",postStats.area));
      valid = false;
    end
    --Orientation Check
    if valid then
      local orientation= postStats.orientation - tiltAngle;
      if (math.abs(orientation) < th_min_orientation) then
        p_vision:add_debug_message(string.format("orientation check fail: %.2f\n",180*orientation/math.pi));
        valid = false;
      end
    end
    --fill extent check
    if valid then
      --Extent good at 0.3 when close to goal posts, better at 0.6 when far
     	--print(unpack(postStats.boundingBox));
      extent = postStats.area / (postStats.axisMajor * postStats.axisMinor);
      local temp_scale = math.sqrt(postStats.area / (postDiameter*postHeight) );
      local coords = HeadTransform.coordinatesA(postStats.centroid, temp_scale);
      local min_extent = th_min_fill_extent[1]
      if (coords[1] > 2) then
        min_extent = th_min_fill_extent[2]
      end
      if (extent < min_extent) then 
        p_vision:add_debug_message(string.format("Fill extent check fail: %.2f\n", extent));
        valid = false; 
      end
    end
    --aspect ratio check
    if valid then
      local aspect = postStats.axisMajor/postStats.axisMinor;
      if (aspect < th_aspect_ratio[1]) or (aspect > th_aspect_ratio[2]) then 
        p_vision:add_debug_message(string.format("Aspect check fail %d\n",aspect));
        valid = false; 
      end
    end
    --check edge margin
    if valid then
      local leftPoint= postStats.centroid[1] - postStats.axisMinor/2 * math.abs(math.cos(tiltAngle));
      local rightPoint= postStats.centroid[1] +	postStats.axisMinor/2 * math.abs(math.cos(tiltAngle));
      local margin = math.min(leftPoint,p_vision.labelA.m-rightPoint);
      if margin<=th_edge_margin then
        p_vision:add_debug_message(string.format("Edge margin check fail: %d\n",margin));
        valid = false;
      end
    end
    -- ground check at the bottom of the post
    if valid and check_for_ground>0 then 
      local bboxA = vcm.bboxB2A(postB[i].boundingBox, p_vision.scaleB);
      if (bboxA[4] < th_bottom_boundingbox * p_vision.labelA.n) then
        -- field bounding box 
        local fieldBBox = {};
        fieldBBox[1] = bboxA[1] + th_ground_boundingbox[1];
        fieldBBox[2] = bboxA[2] + th_ground_boundingbox[2];
        fieldBBox[3] = bboxA[3] + th_ground_boundingbox[3];
        fieldBBox[4] = bboxA[4] + th_ground_boundingbox[4];
        local fieldBBoxStats;
	if use_tilted_bbox>0 then
          print('Error! Nao Robots do not deal with tilted GoalPost')
	else
          fieldBBoxStats = ImageProc.color_stats(p_vision.labelA.data,
            p_vision.labelA.m,p_vision.labelA.n, Config.color.field,fieldBBox,tiltAngle);
	end
        local fieldBBoxArea = vcm.bboxArea(fieldBBox);
	      green_ratio=fieldBBoxStats.area/fieldBBoxArea;
        -- is there green under the post?
        if (green_ratio<th_min_green_ratio) then
          p_vision:add_debug_message(string.format("Green check fail: %.2f\n",green_ratio));
          valid = false;
        end
      end
    end
    --Height Check
    if valid then
      scale = math.sqrt(postStats.area / (postDiameter*postHeight) );
      v = HeadTransform.coordinatesA(postStats.centroid, scale);
      if v[3] < goal_height_min then
        valid = false; 
        p_vision:add_debug_message(string.format("Height check fail:%.2f\n",v[3]));
      elseif v[3] > goal_height_max then
        p_vision:add_debug_message(string.format("Height check fail:%.2f\n",v[3]));
        valid = false;      
      end
    end
    
    --separation Check: Assume the first goal (larger area) is correct
    if (valid and npost==1) then
      local dGoal = math.abs(postStats.centroid[1]-postA[1].centroid[1]);
      local dPost = math.max(postA[1].axisMajor, postStats.axisMajor);
      local separation=dGoal/dPost;
      if (separation<th_goal_separation[1]) then
        p_vision:add_debug_message(string.format("separation check fail:%.2f\n",separation))
        valid = false;
      end
    end


    if (valid) then
      p_vision:add_debug_message("ALL CHECK PASSED\n")
      ivalidB[#ivalidB + 1] = i;
      npost = npost + 1;
      postA[npost] = postStats;
    end
    if (npost==2)then
      break
    end
  end
  
  p_vision:add_debug_message(string.format("=====Total %d valid posts =====\n", npost ));

  if (npost < 1) then
    return 
  end

  self.propsB = {};
  self.propsA = {};
  self.v = {};


  for i = 1,(math.min(npost,2)) do
    self.propsB[i] = postB[ivalidB[i]];
    self.propsA[i] = postA[i];

    scale1 = postA[i].axisMinor / postDiameter;
    scale2 = postA[i].axisMajor / postHeight;
    scale3 = math.sqrt(postA[i].area / (postDiameter*postHeight) );

    if self.propsB[i].boundingBox[3]<2 then 
      --This post is touching the top, so we shouldn't use the height
      p_vision:add_debug_message("Post touching the top\n");
      scale = math.max(scale1,scale3);
    else
      scale = math.max(scale1,scale2,scale3);
    end
    --SJ: goal distance can be noisy, so I added bunch of debug message here
    v1 = HeadTransform.coordinatesA(postA[i].centroid, scale1);
    v2 = HeadTransform.coordinatesA(postA[i].centroid, scale2);
    v3 = HeadTransform.coordinatesA(postA[i].centroid, scale3);
    p_vision:add_debug_message(string.format("Distance by w/h/a : %.1f/%.1f/%.1f\n",
      math.sqrt(v1[1]^2+v1[2]^2), math.sqrt(v2[1]^2+v2[2]^2), math.sqrt(v3[1]^2+v3[2]^2)));

    if scale==scale1 then
      p_vision:add_debug_message("Post distance measured by width\n");
    elseif scale==scale2 then
      p_vision:add_debug_message("Post distance measured by height\n");
    else
      p_vision:add_debug_message("Post distance measured by area\n");
    end

    self.v[i] = HeadTransform.coordinatesA(postA[i].centroid, scale);
    self.v[i][1]=self.v[i][1]*distanceFactorYellow 
    self.v[i][2]=self.v[i][2]*distanceFactorYellow 
    p_vision:add_debug_message(string.format("post[%d] = %.2f %.2f %.2f\n",
      i, self.v[i][1], self.v[i][2], self.v[i][3]));
  end

  if (npost == 2) then
    self.type = 3; --Two posts
  else
    self.v[2] = vector.new({0,0,0,0});
    -- look for crossbar:
    local postWidth = postA[1].axisMinor;
    local leftX = postA[1].boundingBox[1]-5*postWidth;
    local rightX = postA[1].boundingBox[2]+5*postWidth;
    local topY = postA[1].boundingBox[3]-3*postWidth;
    local bottomY = postA[1].boundingBox[3]+1*postWidth;
    local bboxA = {leftX, rightX, topY, bottomY};
    local crossbarStats = ImageProc.color_stats(p_vision.labelA.data, p_vision.labelA.m, p_vision.labelA.n, color, bboxA,tiltAngle);
    local dxCrossbar = crossbarStats.centroid[1] - postA[1].centroid[1];
    local crossbar_ratio = dxCrossbar/postWidth; 
    p_vision:add_debug_message(string.format("Crossbar stat: %.2f\n",crossbar_ratio));
    --If the post touches the top, it should be a unknown post
    if self.propsB[1].boundingBox[3]<3 then --touching the top
      dxCrossbar = 0; --Should be unknown post
    end
    if (math.abs(dxCrossbar) > 0.6*postWidth) then
      if (dxCrossbar > 0) then
	if use_centerpost>0 then
	  self.type = 1;  -- left post
	else
	  self.type = 0;  -- unknown post
	end
      else
	if use_centerpost>0 then
	  self.type = 2;  -- right post
	else
	  self.type = 0;  -- unknown post
	end
      end
    else
      -- unknown post
      self.type = 0;
      -- eliminate small posts without cross bars
      p_vision:add_debug_message(string.format(
	"Unknown single post size check:%d\n",postA[1].area));
      if (postA[1].area < th_min_area_unknown_post) then
        p_vision:add_debug_message("Post size too small");
        return
      end
    end
  end
-- added for test_vision.m
  if Config.vision.copy_image_to_shm then
    vcm.set_goal_postBoundingBox1(postB[ivalidB[1]].boundingBox);
    vcm.set_goal_postCentroid1({postA[1].centroid[1],postA[1].centroid[2]});
    vcm.set_goal_postAxis1({postA[1].axisMajor,postA[1].axisMinor});
    vcm.set_goal_postOrientation1(postA[1].orientation);
    if npost == 2 then
      vcm.set_goal_postBoundingBox2(postB[ivalidB[2]].boundingBox);
      vcm.set_goal_postCentroid2({postA[2].centroid[1],postA[2].centroid[2]});
      vcm.set_goal_postAxis2({postA[2].axisMajor,postA[2].axisMinor});
      vcm.set_goal_postOrientation2(postA[2].orientation);
    else
      vcm.set_goal_postBoundingBox2({0,0,0,0});
    end
  end

  if self.type==0 then
    p_vision:add_debug_message(string.format("Unknown single post detected\n"));
  elseif self.type==1 then
    p_vision:add_debug_message(string.format("Left post detected\n"));
  elseif self.type==2 then
    p_vision:add_debug_message(string.format("Right post detected\n"));
  elseif self.type==3 then
    p_vision:add_debug_message(string.format("Two posts detected\n"));
  end
  self.detect = 1;
  return
end

local update_shm = function(self, p_vision)
  vcm.set_goal_detect(self.detect);
  if (self.detect == 1) then
    vcm.set_goal_color(Config.color.yellow);
    vcm.set_goal_type(self.type);
    vcm.set_goal_v1(self.v[1]);
    vcm.set_goal_v2(self.v[2]);
  end
end

local detectGoal = {}

function detectGoal.entry(parent_vision)
  print('init Goal detection')
  local self = {}
  self.update = update
  self.update_shm = update_shm
  self.detect = 0
  return self
end

return detectGoal
