import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import '../../shared/bottom_nav.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainScaffold(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Stack(
        children: [
          // Background abstract shape/glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.greenPrimary.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(color: AppTheme.greenPrimary.withValues(alpha: 0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.5), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.greenAccent.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.explore_rounded, size: 80, color: AppTheme.greenAccent),
                    ),
                    const SizedBox(height: 32),
                    // App Name
                    const Text(
                      'GeoField Pro',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Professional Mapping Tool',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom Creator Text
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: const Column(
                children: [
                  Text(
                    'CREATED BY',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Kashinath Yankanchi',
                    style: TextStyle(
                      color: AppTheme.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
