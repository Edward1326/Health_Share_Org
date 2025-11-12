import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'staff_dashboard.dart';

// staff_profile.dart
class StaffProfilePage extends StatefulWidget {
  static const String routeName = '/staff_profile';

  const StaffProfilePage({super.key});

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Staff data
  Map<String, dynamic>? staffData;
  Map<String, dynamic>? organizationUserData;
  bool isLoading = true;
  bool isUploadingImage = false;

  // Controllers for editing
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _bloodTypeController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _medicalConditionsController =
      TextEditingController();
  final TextEditingController _disabilitiesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStaffData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _medicalConditionsController.dispose();
    _disabilitiesController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'No authenticated user';

      print('DEBUG: Loading data for user: ${user.id}');

      // Get User data first (contains email) - using email like login service
      final userResponse = await supabase
          .from('User')
          .select('id, email, person_id')
          .eq('email', user.email)
          .single();

      print('DEBUG: User data: $userResponse');
      final userId = userResponse['id'];
      final personId = userResponse['person_id'];
      final userEmail = userResponse['email'];

      // Get Organization_User data with position
      final orgUserResponse = await supabase
          .from('Organization_User')
          .select()
          .eq('user_id', userId)
          .single();

      print('DEBUG: Organization_User data: $orgUserResponse');

      // Get Person data for personal information
      final personResponse =
          await supabase.from('Person').select().eq('id', personId).single();

      print('DEBUG: Person data: $personResponse');

      setState(() {
        organizationUserData = orgUserResponse;
        staffData = personResponse;
        // Store email separately since it comes from User table
        staffData!['email'] = userEmail;
        isLoading = false;

        // Initialize controllers with existing data
        _firstNameController.text = staffData!['first_name'] ?? '';
        _middleNameController.text = staffData!['middle_name'] ?? '';
        _lastNameController.text = staffData!['last_name'] ?? '';
        _emailController.text = userEmail ?? '';
        _addressController.text = staffData!['address'] ?? '';
        _contactNumberController.text = staffData!['contact_number'] ?? '';
        _bloodTypeController.text = staffData!['blood_type'] ?? '';
        _allergiesController.text = staffData!['allergies'] ?? '';
        _medicalConditionsController.text =
            staffData!['medical_conditions'] ?? '';
        _disabilitiesController.text = staffData!['disabilities'] ?? '';
      });

      print('DEBUG: Data loaded successfully with email: $userEmail');
    } catch (error) {
      print('DEBUG: Error loading data: $error');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading staff data: $error'),
            backgroundColor: Colors.red,
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

      // Generate unique filename
      final fileName =
          'staff_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Read image as bytes (works for both web and mobile)
      final bytes = await image.readAsBytes();
      await _uploadImageBytes(bytes, fileName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading image: $error'),
            backgroundColor: Colors.red,
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
    // Upload to storage bucket
    await supabase.storage.from('profile-images').uploadBinary(fileName, bytes);

    // Get public URL
    final imageUrl =
        supabase.storage.from('profile-images').getPublicUrl(fileName);

    // Update person record (image is stored in Person table)
    await _updateStaffImage(imageUrl);
  }

  Future<void> _updateStaffImage(String imageUrl) async {
    await supabase
        .from('Person')
        .update({'image': imageUrl}).eq('id', staffData!['id']);

    // Reload data to show updated image
    await _loadStaffData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile image updated successfully!'),
          backgroundColor: Color(0xFF4A8B3A),
        ),
      );
    }
  }

  Future<void> _updateStaffData() async {
    try {
      // Update Person table - removed current_medications
      await supabase.from('Person').update({
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'address': _addressController.text.trim(),
        'contact_number': _contactNumberController.text.trim(),
        'blood_type': _bloodTypeController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'medical_conditions': _medicalConditionsController.text.trim(),
        'disabilities': _disabilitiesController.text.trim(),
      }).eq('id', staffData!['id']);

      await _loadStaffData();

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF4A8B3A),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $error'),
            backgroundColor: Colors.red,
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

  String _getFullName() {
    if (staffData == null) return 'Unknown Staff';

    final firstName = staffData!['first_name'] ?? '';
    final middleName = staffData!['middle_name'] ?? '';
    final lastName = staffData!['last_name'] ?? '';

    return '$firstName ${middleName.isNotEmpty ? '$middleName ' : ''}$lastName'
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return MainStaffDashboardLayout(
      title: 'My Profile',
      selectedNavIndex: 1, // Changed from 4 to 1
      content: _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4A8B3A),
        ),
      );
    }

    if (staffData == null || organizationUserData == null) {
      return const Center(
        child: Text(
          'No staff data found',
          style: TextStyle(fontSize: 16, color: Color(0xFF6C757D)),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
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
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF4A8B3A),
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF4A8B3A),
                        backgroundImage: staffData!['image'] != null
                            ? NetworkImage(staffData!['image'])
                            : null,
                        child: staffData!['image'] == null
                            ? const Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.white,
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
                            color: const Color(0xFF4A8B3A),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          child: isUploadingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
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
                const SizedBox(height: 16),
                Text(
                  _getFullName(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF495057),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A8B3A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    organizationUserData!['position'] ?? 'Staff',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4A8B3A),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Personal Information Section
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF495057),
            ),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Full Name',
            _getFullName(),
            Icons.person,
            const Color(0xFF4A8B3A),
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Email Address',
            staffData!['email'] ?? 'Not specified',
            Icons.email,
            const Color(0xFF6BA85A),
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Contact Number',
            staffData!['contact_number'] ?? 'Not specified',
            Icons.phone,
            Colors.blue,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Address',
            staffData!['address'] ?? 'Not specified',
            Icons.location_on,
            Colors.orange,
          ),

          const SizedBox(height: 24),

          // Medical Information Section
          const Text(
            'Medical Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF495057),
            ),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Blood Type',
            staffData!['blood_type'] ?? 'Not specified',
            Icons.bloodtype,
            Colors.red,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Allergies',
            staffData!['allergies'] ?? 'None specified',
            Icons.warning,
            Colors.orange,
            isMultiline: true,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Medical Conditions',
            staffData!['medical_conditions'] ?? 'None specified',
            Icons.medical_services,
            Colors.purple,
            isMultiline: true,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Disabilities',
            staffData!['disabilities'] ?? 'None specified',
            Icons.accessibility,
            Colors.blue,
            isMultiline: true,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Member Since',
            _formatDateTime(staffData!['created_at']),
            Icons.calendar_today,
            const Color(0xFF6C757D),
          ),

          const SizedBox(height: 32),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                _showEditDialog(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A8B3A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

  Widget _buildInfoCard(
      String title, String content, IconData icon, Color iconColor,
      {bool isMultiline = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6C757D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF495057),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: isMultiline ? null : 2,
                  overflow: isMultiline ? null : TextOverflow.ellipsis,
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
    _firstNameController.text = staffData!['first_name'] ?? '';
    _middleNameController.text = staffData!['middle_name'] ?? '';
    _lastNameController.text = staffData!['last_name'] ?? '';
    _emailController.text = staffData!['email'] ?? '';
    _addressController.text = staffData!['address'] ?? '';
    _contactNumberController.text = staffData!['contact_number'] ?? '';
    _bloodTypeController.text = staffData!['blood_type'] ?? '';
    _allergiesController.text = staffData!['allergies'] ?? '';
    _medicalConditionsController.text = staffData!['medical_conditions'] ?? '';
    _disabilitiesController.text = staffData!['disabilities'] ?? '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          backgroundColor: const Color(0xFFF8F9FA),
          title: const Text(
            'Edit Profile',
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
                  // Personal Information
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _middleNameController,
                    label: 'Middle Name (Optional)',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _lastNameController,
                    label: 'Last Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _contactNumberController,
                    label: 'Contact Number',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // Medical Information
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Medical Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF495057),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _bloodTypeController,
                    label: 'Blood Type (e.g., A+, B-, O+)',
                    icon: Icons.bloodtype,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _allergiesController,
                    label: 'Allergies',
                    icon: Icons.warning,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _medicalConditionsController,
                    label: 'Medical Conditions',
                    icon: Icons.medical_services,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _disabilitiesController,
                    label: 'Disabilities',
                    icon: Icons.accessibility,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
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
              onPressed: _updateStaffData,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF495057),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFF6C757D),
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF6C757D),
          size: 20,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4A8B3A), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
