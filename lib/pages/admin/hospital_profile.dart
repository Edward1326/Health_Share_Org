import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'admin_dashboard.dart'; // Import for DashboardTheme

// Modern Hospital Profile Content Widget
class HospitalProfileContentWidget extends StatefulWidget {
  final String? organizationId;

  const HospitalProfileContentWidget({
    Key? key,
    this.organizationId,
  }) : super(key: key);

  @override
  State<HospitalProfileContentWidget> createState() =>
      _HospitalProfileContentWidgetState();
}

class _HospitalProfileContentWidgetState
    extends State<HospitalProfileContentWidget> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Use DashboardTheme colors
  static const primaryGreen = DashboardTheme.primaryGreen;
  static const textGray = DashboardTheme.textGray;

  // Organization data
  Map<String, dynamic>? organizationData;
  bool isLoading = true;
  bool isUploadingImage = false;
  String? currentOrganizationId;

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
    currentOrganizationId = widget.organizationId;
    _initializeAndLoad();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get organization ID from route if not already set
    if (currentOrganizationId == null) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['organizationId'] != null) {
        currentOrganizationId = args['organizationId'];
        _initializeAndLoad();
      }
    }
  }

  @override
  void didUpdateWidget(HospitalProfileContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if organization ID changes
    if (oldWidget.organizationId != widget.organizationId) {
      currentOrganizationId = widget.organizationId;
      _initializeAndLoad();
    }
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

  Future<void> _initializeAndLoad() async {
    await _fetchOrganizationId();
    await _loadOrganizationData();
  }

  Future<void> _fetchOrganizationId() async {
    try {
      // If already set, skip
      if (currentOrganizationId != null) {
        print('✅ Using organization ID: $currentOrganizationId');
        return;
      }

      final authUser = supabase.auth.currentUser;
      if (authUser == null) {
        throw Exception("No user logged in");
      }

      print('🔍 Fetching organization for auth user: ${authUser.id}');

      // Step 1: Get Person record from auth user
      final personResponse = await supabase
          .from('Person')
          .select('id')
          .eq('auth_user_id', authUser.id)
          .single();

      final personId = personResponse['id'] as String;
      print('✅ Person ID: $personId');

      // Step 2: Get User record from Person
      final userResponse = await supabase
          .from('User')
          .select('id')
          .eq('person_id', personId)
          .single();

      final userId = userResponse['id'] as String;
      print('✅ User ID: $userId');

      // Step 3: Get organization from Organization_User
      final orgUserResponse = await supabase
          .from('Organization_User')
          .select('organization_id')
          .eq('user_id', userId)
          .single();

      currentOrganizationId = orgUserResponse['organization_id'] as String?;
      print('✅ Organization ID fetched: $currentOrganizationId');
    } catch (e) {
      print('❌ Error fetching organization ID: $e');
      rethrow;
    }
  }

  Future<void> _loadOrganizationData() async {
    try {
      setState(() {
        isLoading = true;
      });

      if (currentOrganizationId == null) {
        throw Exception('No organization ID available');
      }

      print('📋 Loading organization data for: $currentOrganizationId');

      // Load the SPECIFIC organization by ID
      final response = await supabase
          .from('Organization')
          .select()
          .eq('id', currentOrganizationId!)
          .single();

      print('✅ Organization loaded: ${response['name']}');

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
      print('❌ Error loading organization: $error');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading organization data: $error'),
            backgroundColor: Colors.red,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

      setState(() {
        isUploadingImage = true;
      });

      final fileName =
          'organization_${currentOrganizationId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await image.readAsBytes();
      await _uploadImageBytes(bytes, fileName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $error'),
            backgroundColor: Colors.red,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        isUploadingImage = false;
      });
    }
  }

  Future<void> _uploadImageBytes(Uint8List bytes, String fileName) async {
    await supabase.storage.from('profile-images').uploadBinary(fileName, bytes);
    final imageUrl =
        supabase.storage.from('profile-images').getPublicUrl(fileName);
    await _updateOrganizationImage(imageUrl);
  }

  Future<void> _updateOrganizationImage(String imageUrl) async {
    await supabase
        .from('Organization')
        .update({'image': imageUrl}).eq('id', currentOrganizationId!);

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
      }).eq('id', currentOrganizationId!);

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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

      // Format with date and time
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year;
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');

      return '$day/$month/$year $hour:$minute';
    } catch (e) {
      return 'Invalid date';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryGreen),
      );
    }

    if (organizationData == null) {
      return Center(
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
            Text(
              currentOrganizationId != null
                  ? 'Organization ID: $currentOrganizationId'
                  : 'No organization ID available',
              style: const TextStyle(
                fontSize: 12,
                color: textGray,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your database or contact support.',
              style: TextStyle(
                fontSize: 14,
                color: textGray,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializeAndLoad,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and action button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hospital Profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  if (currentOrganizationId != null)
                    Text(
                      'ID: $currentOrganizationId',
                      style: const TextStyle(
                        fontSize: 11,
                        color: textGray,
                      ),
                    ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit Profile'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Profile card
          _buildProfileCard(),

          const SizedBox(height: 24),

          // Information sections
          _buildInformationSections(),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
          // Profile header with image
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Profile image
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: primaryGreen, width: 3),
                        color: Colors.white,
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: primaryGreen.withOpacity(0.1),
                        backgroundImage: organizationData!['image'] != null
                            ? NetworkImage(organizationData!['image'])
                            : null,
                        child: organizationData!['image'] == null
                            ? const Icon(
                                Icons.local_hospital,
                                size: 40,
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
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 14,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                // Hospital info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        organizationData!['name'] ?? 'Unknown Hospital',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (organizationData!['description'] != null)
                        Text(
                          organizationData!['description'],
                          style: const TextStyle(
                            fontSize: 14,
                            color: textGray,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick stats row
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickStat(
                    Icons.verified_user,
                    'License',
                    organizationData!['organization_license'] ?? 'N/A',
                    DashboardTheme.approvedGreen,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFFE5E7EB),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Expanded(
                  child: _buildQuickStat(
                    Icons.calendar_today,
                    'Registered',
                    _formatDateTime(organizationData!['created_at']),
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: textGray,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInformationSections() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Contact Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          _buildInfoItem(
            Icons.location_on,
            'Location',
            organizationData!['location'] ?? 'Not specified',
            Colors.orange,
          ),
          _buildInfoItem(
            Icons.email,
            'Email Address',
            organizationData!['email'] ?? 'Not specified',
            Colors.teal,
          ),
          _buildInfoItem(
            Icons.phone,
            'Contact Number',
            organizationData!['contact_number'] ?? 'Not specified',
            Colors.blue,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value, Color color,
      {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: textGray,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ],
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
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          backgroundColor: const Color(0xFFF8F9FA),
          title: const Text(
            'Edit Hospital Profile',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Color(0xFF495057),
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hospital Information
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Hospital Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _nameController,
                    label: 'Hospital Name',
                    icon: Icons.local_hospital,
                    hint: 'Enter hospital name',
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _descriptionController,
                    label: 'Description',
                    icon: Icons.description,
                    hint: 'Enter hospital description',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _licenseController,
                    label: 'License Number',
                    icon: Icons.verified_user,
                    hint: 'Enter license number',
                  ),
                  const SizedBox(height: 20),

                  // Contact Information
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Contact Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _locationController,
                    label: 'Location',
                    icon: Icons.location_on,
                    hint: 'Enter hospital address',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email,
                    hint: 'Enter email address',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildEditField(
                    controller: _contactController,
                    label: 'Contact Number',
                    icon: Icons.phone,
                    hint: 'Enter contact number',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                  )
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6C757D),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _updateOrganizationData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A8B3A),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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
    List<TextInputFormatter>? inputFormatters, // Add this parameter
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters, // Add this line
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF4A8B3A), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4A8B3A), width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        alignLabelWithHint: maxLines > 1,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFF6C757D),
        ),
        hintStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFFADB5BD),
        ),
      ),
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF495057),
      ),
    );
  }
}

// Updated Hospital Profile Page using modular layout
class ModernAdminProfilePage extends StatelessWidget {
  final String? organizationId;

  const ModernAdminProfilePage({
    Key? key,
    this.organizationId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Try to get organizationId from route if not provided
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final orgId = organizationId ?? args?['organizationId'];

    // Always use modular layout with sidebar
    return MainDashboardLayout(
      title: 'Hospital Profile',
      selectedNavIndex: 3,
      content: HospitalProfileContentWidget(organizationId: orgId),
    );
  }
}
