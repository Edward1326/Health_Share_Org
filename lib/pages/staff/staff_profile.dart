import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

// doctor_profile.dart
class DoctorProfilePage extends StatefulWidget {
  // Add route name constant for easy reference
  static const String routeName = '/doctor_profile';

  const DoctorProfilePage({super.key});

  @override
  State<DoctorProfilePage> createState() => _DoctorProfilePageState();
}

class _DoctorProfilePageState extends State<DoctorProfilePage> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Doctor data
  Map<String, dynamic>? doctorData;
  Map<String, dynamic>? organizationUserData;
  bool isLoading = true;
  bool isUploadingImage = false;

  // Controllers for editing
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNumberController = TextEditingController();
  final TextEditingController _bloodTypeController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _medicalConditionsController = TextEditingController();
  final TextEditingController _currentMedicationsController = TextEditingController();
  final TextEditingController _disabilitiesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
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
    _currentMedicationsController.dispose();
    _disabilitiesController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctorData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'No authenticated user';

      print('DEBUG: Loading data for user: ${user.id}');

      // Get Organization_User data with position
      final orgUserResponse = await supabase
          .from('Organization_User')
          .select()
          .eq('user_id', user.id)
          .single();

      print('DEBUG: Organization_User data: $orgUserResponse');

      // Get Person data for personal information
      final personResponse = await supabase
          .from('Person')
          .select()
          .eq('auth_user_id', user.id)
          .single();

      print('DEBUG: Person data: $personResponse');

      setState(() {
        organizationUserData = orgUserResponse;
        doctorData = personResponse;
        isLoading = false;

        // Initialize controllers with existing data
        _firstNameController.text = doctorData!['first_name'] ?? '';
        _middleNameController.text = doctorData!['middle_name'] ?? '';
        _lastNameController.text = doctorData!['last_name'] ?? '';
        _emailController.text = doctorData!['email'] ?? '';
        _addressController.text = doctorData!['address'] ?? '';
        _contactNumberController.text = doctorData!['contact_number'] ?? '';
        _bloodTypeController.text = doctorData!['blood_type'] ?? '';
        _allergiesController.text = doctorData!['allergies'] ?? '';
        _medicalConditionsController.text = doctorData!['medical_conditions'] ?? '';
        _currentMedicationsController.text = doctorData!['current_medications'] ?? '';
        _disabilitiesController.text = doctorData!['disabilities'] ?? '';
      });

      print('DEBUG: Data loaded successfully');
    } catch (error) {
      print('DEBUG: Error loading data: $error');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading doctor data: $error'),
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
          'doctor_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

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
    await _updateDoctorImage(imageUrl);
  }

  Future<void> _updateDoctorImage(String imageUrl) async {
    await supabase
        .from('Person')
        .update({'image': imageUrl}).eq('id', doctorData!['id']);

    // Reload data to show updated image
    await _loadDoctorData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile image updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _updateDoctorData() async {
    try {
      // Update Person table
      await supabase.from('Person').update({
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'contact_number': _contactNumberController.text.trim(),
        'blood_type': _bloodTypeController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'medical_conditions': _medicalConditionsController.text.trim(),
        'current_medications': _currentMedicationsController.text.trim(),
        'disabilities': _disabilitiesController.text.trim(),
      }).eq('id', doctorData!['id']);

      await _loadDoctorData();

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
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
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _getFullName() {
    if (doctorData == null) return 'Unknown Doctor';
    
    final firstName = doctorData!['first_name'] ?? '';
    final middleName = doctorData!['middle_name'] ?? '';
    final lastName = doctorData!['last_name'] ?? '';
    
    return '$firstName ${middleName.isNotEmpty ? '$middleName ' : ''}$lastName'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Doctor Profile',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2D3748)),
        shadowColor: Colors.black.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDoctorData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : (doctorData == null || organizationUserData == null)
              ? const Center(
                  child: Text(
                    'No doctor data found',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Header Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
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
                                      color: const Color(0xFF3182CE),
                                      width: 3,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: const Color(0xFF3182CE),
                                    backgroundImage:
                                        doctorData!['image'] != null
                                            ? NetworkImage(doctorData!['image'])
                                            : null,
                                    child: doctorData!['image'] == null
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
                                    onTap: isUploadingImage
                                        ? null
                                        : _pickAndUploadImage,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3182CE),
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
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
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
                              'Dr. ${_getFullName()}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              organizationUserData!['position'] ?? 'Doctor',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Personal Information Section
                      const Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        'Full Name',
                        _getFullName(),
                        Icons.person,
                        const Color(0xFF3182CE),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Email Address',
                        doctorData!['email'] ?? 'Not specified',
                        Icons.email,
                        const Color(0xFF38B2AC),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Contact Number',
                        doctorData!['contact_number'] ?? 'Not specified',
                        Icons.phone,
                        const Color(0xFF4299E1),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Address',
                        doctorData!['address'] ?? 'Not specified',
                        Icons.location_on,
                        const Color(0xFFED8936),
                      ),

                      const SizedBox(height: 24),

                      // Medical Information Section
                      const Text(
                        'Medical Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildInfoCard(
                        'Blood Type',
                        doctorData!['blood_type'] ?? 'Not specified',
                        Icons.bloodtype,
                        const Color(0xFFE53E3E),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Allergies',
                        doctorData!['allergies'] ?? 'None specified',
                        Icons.warning,
                        const Color(0xFFED8936),
                        isMultiline: true,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Medical Conditions',
                        doctorData!['medical_conditions'] ?? 'None specified',
                        Icons.medical_services,
                        const Color(0xFF9F7AEA),
                        isMultiline: true,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Current Medications',
                        doctorData!['current_medications'] ?? 'None specified',
                        Icons.medication,
                        const Color(0xFF38A169),
                        isMultiline: true,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Disabilities',
                        doctorData!['disabilities'] ?? 'None specified',
                        Icons.accessibility,
                        const Color(0xFF4299E1),
                        isMultiline: true,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        'Registered On',
                        _formatDateTime(doctorData!['created_at']),
                        Icons.calendar_today,
                        const Color(0xFF718096),
                      ),

                      const SizedBox(height: 32),

                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            _showEditDialog(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3182CE),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoCard(
      String title, String content, IconData icon, Color iconColor, {bool isMultiline = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
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
    _firstNameController.text = doctorData!['first_name'] ?? '';
    _middleNameController.text = doctorData!['middle_name'] ?? '';
    _lastNameController.text = doctorData!['last_name'] ?? '';
    _emailController.text = doctorData!['email'] ?? '';
    _addressController.text = doctorData!['address'] ?? '';
    _contactNumberController.text = doctorData!['contact_number'] ?? '';
    _bloodTypeController.text = doctorData!['blood_type'] ?? '';
    _allergiesController.text = doctorData!['allergies'] ?? '';
    _medicalConditionsController.text = doctorData!['medical_conditions'] ?? '';
    _currentMedicationsController.text = doctorData!['current_medications'] ?? '';
    _disabilitiesController.text = doctorData!['disabilities'] ?? '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Doctor Profile',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _middleNameController,
                    decoration: const InputDecoration(
                      labelText: 'Middle Name (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contactNumberController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Medical Information
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Medical Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bloodTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Blood Type (e.g., A+, B-, O+)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.bloodtype),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _allergiesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Allergies',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.warning),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _medicalConditionsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Medical Conditions',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.medical_services),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _currentMedicationsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Current Medications',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.medication),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _disabilitiesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Disabilities',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.accessibility),
                      alignLabelWithHint: true,
                    ),
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: _updateDoctorData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3182CE),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}