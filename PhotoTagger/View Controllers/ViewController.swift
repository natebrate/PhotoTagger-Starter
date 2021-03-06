/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import SwiftyJSON
import Alamofire

class ViewController: UIViewController {

  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!

  // MARK: - Properties
  private var tags: [String]?
  private var colors: [PhotoColor]?

  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()

    if !UIImagePickerController.isSourceTypeAvailable(.camera) {
      takePictureButton.setTitle("Select Photo", for: .normal)
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    imageView.image = nil
  }

  // MARK: - Navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

    if segue.identifier == "ShowResults",
      let controller = segue.destination as? TagsColorsViewController {
      controller.tags = tags
      controller.colors = colors
    }
  }

  // MARK: - IBActions
  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }

    present(picker, animated: true)
  }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true)
      return
    }

    imageView.image = image
    // 1
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()

    upload(image: image,
           progressCompletion: { [weak self] percent in
            // 2
            self?.progressView.setProgress(percent, animated: true)
      },
           completion: { [weak self] tags, colors in
            // 3
            self?.takePictureButton.isHidden = false
            self?.progressView.isHidden = true
            self?.activityIndicatorView.stopAnimating()
                
            self?.tags = tags
            self?.colors = colors
                
            // 4
            self?.performSegue(withIdentifier: "ShowResults", sender: self)
    })

    dismiss(animated: true)
  }
}

//MARK: - Networking calls
extension ViewController {
 func upload(image: UIImage,
              progressCompletion: @escaping (_ percent: Float) -> Void,
              completion: @escaping (_ tags: [String]?, _ colors: [PhotoColor]?) -> Void) {
    // 1
  guard let imageData = image.jpegData(compressionQuality: 0.5) else {
      print("Could not get JPEG representation of UIImage")
      return
    }

    // 2
    Alamofire.upload(multipartFormData: { multipartFormData in
      multipartFormData.append(imageData,
                               withName: "imagefile",
                               fileName: "image.jpg",
                               mimeType: "image/jpeg")
    },
                     to: "http://api.imagga.com/v1/content",
                     headers: ["Authorization": "Basic YWNjXzE1YzI4Y2ZkZDY4MTA5YzpmNDFjNmViZDA0MTVkNTBkZmU3YjkzYjFkZWExZDg0ZQ=="],
                     encodingCompletion: { encodingResult in
                      switch encodingResult {
                      case .success(let upload, _, _):
                        upload.uploadProgress { progress in
                          progressCompletion(Float(progress.fractionCompleted))
                        }
                        upload.validate()
                        upload.responseJSON { response in
                          // 1
                          guard response.result.isSuccess,
                            let value = response.result.value else {
                              print("Error while uploading file: \(String(describing: response.result.error))")
                              completion(nil, nil)
                              return
                          }
                                                  
                          // 2
                          let firstFileID = JSON(value)["uploaded"][0]["id"].stringValue
                          print("Content uploaded with ID: \(firstFileID)")
                                                  
                          //3
                          self.downloadTags(contentID: firstFileID) { tags in
                            self.downloadColors(contentID: firstFileID) { colors in
                              completion(tags, colors)
                            }
                          }
                        }
                      case .failure(let encodingError):
                        print(encodingError)
                      }
    })
  }

  func downloadTags(contentID: String, completion: @escaping ([String]?) -> Void) {
    // 1
    Alamofire.request("http://api.imagga.com/v1/tagging",
                      parameters: ["content": contentID],
                      headers: ["Authorization": "Basic YWNjXzE1YzI4Y2ZkZDY4MTA5YzpmNDFjNmViZDA0MTVkNTBkZmU3YjkzYjFkZWExZDg0ZQ=="])
       // 2
      .responseJSON { response in
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching tags: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
        
        // 3
        let tags = JSON(value)["results"][0]["tags"].array?.map { json in
          json["tag"].stringValue
        }
          
        // 4
        completion(tags)
    }
  }
  
  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]?) -> Void) {
    // 1.
    Alamofire.request("http://api.imagga.com/v1/colors",
                      parameters: ["content": contentID],
                      headers: ["Authorization": "Basic YWNjXzE1YzI4Y2ZkZDY4MTA5YzpmNDFjNmViZDA0MTVkNTBkZmU3YjkzYjFkZWExZDg0ZQ=="])
      .responseJSON { response in
        // 2
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching colors: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
          
        // 3
        let photoColors = JSON(value)["results"][0]["info"]["image_colors"].array?.map { json in
          PhotoColor(red: json["r"].intValue,
                     green: json["g"].intValue,
                     blue: json["b"].intValue,
                     colorName: json["closest_palette_color"].stringValue)
        }
          
        // 4
        completion(photoColors)
    }
  }
}
