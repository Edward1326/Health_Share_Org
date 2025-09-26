import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'admin_dashboard.dart'; // Import for DashboardTheme

// Modern Hospital Profile Content Widget
class HospitalProfileContentWidget extends StatefulWidget {
  const HospitalProfileContentWidget({Key? key}) : super(key: key);

  @override
  State<HospitalProfileContentWidget> createState() => _HospitalProfileContentWidgetState();
}

class _HospitalProfileContentWidgetState extends State<HospitalProfileContentWidget> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Use DashboardTheme colors
  static const primaryGreen = DashboardTheme.primaryGreen;
  static const textGray = DashboardTheme.textGray;
  static const cardBackground = DashboardTheme.cardBackground;

  // Organization data
  Map<String, dynamic>? organizationData;
  bool isLoading = true;
  bool isUploadingImage = false;

  // Controllers for editing
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrganizationData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _licenseController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizationData() async {
    try {
      setState(() { isLoading = true; });

      final response = await supabase.from('Organization').select().single();

      setState(() {
        organizationData = response;
        isLoading = false;

        // Initialize controllers with existing data
        _nameController.text = response['name'] ?? '';
        _licenseController.text = response['organization_license'] ?? '';
        _descriptionController.text = response['description'] ?? '';
        _locationController.text = response['location'] ?? '';
        _emailController.text = response['email'] ?? '';
        _contactController.text = response['contact_number'] ?? '';
      });
    } catch (error) {
      setState(() { isLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading organization data: $error'),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() { isUploadingImage = true; });

      final fileName = 'organization_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await image.readAsBytes();
      await _uploadImageBytes(bytes, fileName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $error'),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() { isUploadingImage = false; });
    }
  }

  Future<void> _uploadImageBytes(Uint8List bytes, String fileName) async {
    await supabase.storage.from('profile-images').uploadBinary(fileName, bytes);
    final imageUrl = supabase.storage.from('profile-images').getPublicUrl(fileName);
    await _updateOrganizationImage(imageUrl);
  }

  Future<void> _updateOrganizationImage(String imageUrl) async {
    await supabase
        .from('Organization')
        .update({'image': imageUrl}).eq('id', organizationData!['id']);

    await _loadOrganizationData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Profile image updated successfully!'),
            ],
          ),
          backgroundColor: DashboardTheme.approvedGreen,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateOrganizationData() async {
    try {
      await supabase.from('Organization').update({
        'name': _nameController.text.trim(),
        'organization_license': _licenseController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'email': _emailController.text.trim(),
        'contact_number': _contactController.text.trim(),
      }).eq('id', organizationData!['id']);

      await _loadOrganizationData();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Profile updated successfully!'),
              ],
            ),
            backgroundColor: DashboardTheme.approvedGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $error'),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return 'Not available';
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Hospital Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadOrganizationData,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryGreen,
                      side: const BorderSide(color: primaryGreen),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: organizationData == null ? null : () => _showEditDialog(context),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Main content area
          if (isLoading)
            _buildLoadingCard()
          else if (organizationData == null)
            _buildErrorCard()
          else
            Column(
              children: [
                // Profile overview card
                _buildProfileOverviewCard(),
                const SizedBox(height: 24),
                
                // Information cards grid
                _buildInformationGrid(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryGreen),
            SizedBox(height: 16),
            Text(
              'Loading hospital profile...',
              style: TextStyle(
                fontSize: 16,
                color: textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No hospital profile found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your database connection or create a profile.',
              style: TextStyle(
                fontSize: 14,
                color: textGray,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOverviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile image with edit overlay
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryGreen, width: 3),
                ),
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: primaryGreen.withOpacity(0.1),
                  backgroundImage: organizationData!['image'] != null
                      ? NetworkImage(organizationData!['image'])
                      : null,
                  child: organizationData!['image'] == null
                      ? const Icon(
                          Icons.local_hospital,
                          size: 48,
                          color: primaryGreen,
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: isUploadingImage ? null : _pickAndUploadImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isUploadingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Hospital name
          Text(
            organizationData!['name'] ?? 'Unknown Hospital',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          
          // Description
          if (organizationData!['description'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                organizationData!['description'],
                style: const TextStyle(
                  fontSize: 16,
                  color: textGray,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInformationGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column
        Expanded(
          child: Column(
            children: [
              _buildInfoCard(
                'Hospital Name',
                organizationData!['name'] ?? 'Not specified',
                Icons.local_hospital,
                primaryGreen,
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Location',
                organizationData!['location'] ?? 'Not specified',
                Icons.location_on,
                Colors.orange,
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Contact Number',
                organizationData!['contact_number'] ?? 'Not specified',
                Icons.phone,
                Colors.blue,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        
        // Right column
        Expanded(
          child: Column(
            children: [
              _buildInfoCard(
                'Email Address',
                organizationData!['email'] ?? 'Not specified',
                Icons.email,
                Colors.teal,
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'License Number',
                organizationData!['organization_license'] ?? 'Not specified',
                Icons.verified_user,
                DashboardTheme.approvedGreen,
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Registration Date',
                _formatDateTime(organizationData!['created_at']),
                Icons.calendar_today,
                Colors.purple,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String content, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textGray,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            content,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    // Reset controllers with current data
    _nameController.text = organizationData!['name'] ?? '';
    _licenseController.text = organizationData!['organization_license'] ?? '';
    _descriptionController.text = organizationData!['description'] ?? '';
    _locationController.text = organizationData!['location'] ?? '';
    _emailController.text = organizationData!['email'] ?? '';
    _contactController.text = organizationData!['contact_number'] ?? '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dialog header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Hospital Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Form fields
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildEditField(
                          controller: _nameController,
                          label: 'Hospital Name',
                          icon: Icons.local_hospital,
                          hint: 'Enter hospital name',
                        ),
                        const SizedBox(height: 16),
                        _buildEditField(
                          controller: _descriptionController,
                          label: 'Description',
                          icon: Icons.description,
                          hint: 'Enter hospital description',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        _buildEditField(
                          controller: _locationController,
                          label: 'Location',
                          icon: Icons.location_on,
                          hint: 'Enter hospital address',
                        ),
                        const SizedBox(height: 16),
                        _buildEditField(
                          controller: _emailController,
                          label: 'Email Address',
                          icon: Icons.email,
                          hint: 'Enter email address',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        _buildEditField(
                          controller: _contactController,
                          label: 'Contact Number',
                          icon: Icons.phone,
                          hint: 'Enter contact number',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        _buildEditField(
                          controller: _licenseController,
                          label: 'License Number',
                          icon: Icons.verified_user,
                          hint: 'Enter license number',
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Dialog actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textGray,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _updateOrganizationData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: primaryGreen),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        alignLabelWithHint: maxLines > 1,
      ),
      style: const TextStyle(
        fontSize: 14,
        color: Colors.black,
      ),
    );
  }
}

// Updated Hospital Profile Page using modular layout
class ModernAdminProfilePage extends StatelessWidget {
  const ModernAdminProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;

    if (isSmallScreen) {
      // Mobile - simple scaffold
      return Scaffold(
        backgroundColor: DashboardTheme.sidebarGray,
        appBar: AppBar(
          title: const Text('Hospital Profile'),
          backgroundColor: DashboardTheme.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const HospitalProfileContentWidget(),
      );
    }

    // Desktop - use modular layout
    return const MainDashboardLayout(
      title: 'Hospital Profile',
      selectedNavIndex: 3,
      content: HospitalProfileContentWidget(),
    );
  }
}