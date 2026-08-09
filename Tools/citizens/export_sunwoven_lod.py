import bpy
blend='Tools/citizens/assets/sunwoven_lab.blend'
out='ThreeRuntime/assets/units/sunwoven_foundation_citizen_lod.glb'
bpy.ops.wm.open_mainfile(filepath=blend)
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE' and o.name=='sunwoven_armature')
parts=[arm]+[o for o in bpy.data.objects if o.type=='MESH' and o.find_armature()==arm]
for o in bpy.context.selected_objects: o.select_set(False)
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active=arm
for o in parts:
    if o.type!='MESH': continue
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new('foundation_citizen_lod','DECIMATE'); mod.ratio=0.38
    bpy.ops.object.modifier_apply(modifier=mod.name); o.select_set(False)
arm.select_set(True); bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True, export_apply=False, export_animations=True, export_animation_mode='ACTIONS', export_frame_range=False, export_current_frame=False, export_bake_animation=False, export_force_sampling=False, export_def_bones=False, export_extras=True, export_skins=True, export_morph=False)
print('[lod] exported',out)

# end

