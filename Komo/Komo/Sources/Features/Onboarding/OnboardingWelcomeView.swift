import SwiftUI

struct OnboardingWelcomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("userName") private var userName = ""
    
    @State private var inputName = ""
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "172B21")
                .ignoresSafeArea()
            
            // Soft center glow
            Circle()
                .fill(Color(hex: "81A365").opacity(0.6))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(y: -150)
            
            VStack {
                Spacer()
                
                // Avatar (Glossy Orb)
                KomoOrbView()
                    .frame(width: 160, height: 160)
                    .padding(.bottom, 40)
                
                // Title
                Text("K O M O")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .kerning(8) // Letter spacing
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
                
                // Subtitle
                Text("a little light, brought through the\nleaves of your days")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 60)
                
                // Input Section
                VStack(spacing: 12) {
                    Text("What's your name?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    
                    TextField("Maya", text: $inputName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "3A5343"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "5A7A61"), lineWidth: 1)
                        )
                        .padding(.horizontal, 30)
                }
                .padding(.bottom, 24)
                
                // Main Button
                Button(action: {
                    withAnimation(.easeInOut) {
                        let finalName = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
                        userName = finalName.isEmpty ? "Friend" : finalName
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text("Meet your KOMO")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                
                // Footer
                Button(action: {
                    // Action for already having a companion (skip for now)
                    withAnimation(.easeInOut) {
                        userName = "Sacha" // default
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text("I already have a companion")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                Spacer()
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Glossy Orb Avatar
struct KomoOrbView: View {
    var body: some View {
        ZStack {
            // Base shape with main gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "4AC5AD"), Color(hex: "1B7E6F")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Top highlight for 3D glossy effect
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .scaleEffect(0.85)
                .offset(y: -10)
                .blur(radius: 5)
            
            // Bright specular highlight (the white dot)
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .blur(radius: 4)
                .offset(x: -30, y: -45)
            
            // Bottom rim light
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                .blur(radius: 6)
                .offset(y: 4)
                .mask(Circle())
            
            // Eyes
            HStack(spacing: 24) {
                KomoEye()
                KomoEye()
            }
            .offset(y: 10)
            
            // Little feet/bumps at the bottom (optional, but in the design)
            HStack(spacing: 30) {
                Circle()
                    .fill(Color(hex: "17655B").opacity(0.5))
                    .frame(width: 20, height: 10)
                    .blur(radius: 2)
                
                Circle()
                    .fill(Color(hex: "17655B").opacity(0.5))
                    .frame(width: 20, height: 10)
                    .blur(radius: 2)
            }
            .offset(y: 65)
        }
        // Drop shadow for the whole orb
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 15)
    }
}

struct KomoEye: View {
    var body: some View {
        ZStack {
            // Sclera (White part)
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            
            // Pupil (Dark part)
            Circle()
                .fill(Color(hex: "1A3A34"))
                .frame(width: 10, height: 10)
                .offset(x: 1) // Slightly looking right
            
            // Eye highlight
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .offset(x: 2, y: -2)
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255
        let blue = Double(rgbValue & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    OnboardingWelcomeView()
}
