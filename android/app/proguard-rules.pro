# R8 混淆防护：保留注解与内部类等属性，避免反射相关异常
-ignorewarnings
-keepattributes *Annotation*, Exceptions, InnerClasses, Signature
