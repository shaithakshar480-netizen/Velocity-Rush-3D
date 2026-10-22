-keep class com.velocityrush3d.firebase.RushFirebaseBridge { *; }
-keepclassmembers class * { @org.godotengine.godot.plugin.UsedByGodot <methods>; }
# Godot discovers these methods through runtime reflection.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
-keep @interface org.godotengine.godot.plugin.UsedByGodot
